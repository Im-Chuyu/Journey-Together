-- Chinese-style area scoring, 7.5 komi, positional superko, no suicide.
-- Life/death is agreed by the players; the engine never guesses dead groups.
local M = {SIZE = 19, KOMI = 7.5}
local N = M.SIZE
local neighbors = {}
for i = 1, N * N do
    local row = {}; neighbors[i] = row
    if i > N then row[#row + 1] = i - N end
    if i <= N * (N - 1) then row[#row + 1] = i + N end
    if (i - 1) % N > 0 then row[#row + 1] = i - 1 end
    if i % N > 0 then row[#row + 1] = i + 1 end
end
local function Copy(board)
    local out = {}; for i = 1, N * N do out[i] = board[i] end; return out
end
local function Key(board)
    -- Four intersections per byte. Exact keys, without collision-prone hashes.
    local chars = {}
    for i = 1, N * N, 4 do
        chars[#chars + 1] = string.char(board[i] + (board[i + 1] or 0) * 4
            + (board[i + 2] or 0) * 16 + (board[i + 3] or 0) * 64)
    end
    return table.concat(chars)
end
local function Group(board, first)
    local stones, seen, liberties, count = {first}, {[first] = true}, {}, 0
    local cursor = 1
    while cursor <= #stones do
        local i = stones[cursor]; cursor = cursor + 1
        for _, j in ipairs(neighbors[i]) do
            if board[j] == 0 and not liberties[j] then liberties[j], count = true, count + 1
            elseif board[j] == board[first] and not seen[j] then seen[j] = true; stones[#stones + 1] = j end
        end
    end
    return stones, count
end
local function Index(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x % 1 ~= 0 or y % 1 ~= 0
        or x < 1 or x > N or y < 1 or y > N then return end
    return (y - 1) * N + x
end
function M.New()
    local board = {}; for i = 1, N * N do board[i] = 0 end
    return {board = board, turn = 1, count = 0, revision = 0, status = "playing",
        seen = {[Key(board)] = true}, passes = 0, captures = {0, 0}}
end
local function Trial(s, i)
    if s.board[i] ~= 0 then return nil, "occupied" end
    local board, captured, checked = Copy(s.board), 0, {}
    board[i] = s.turn
    for _, j in ipairs(neighbors[i]) do
        if board[j] == 3 - s.turn and not checked[j] then
            local stones, liberty = Group(board, j)
            for _, k in ipairs(stones) do checked[k] = true end
            if liberty == 0 then
                for _, k in ipairs(stones) do board[k] = 0; captured = captured + 1 end
            end
        end
    end
    local _, liberty = Group(board, i)
    if liberty == 0 then return nil, "suicide" end
    local key = Key(board)
    if s.seen[key] then return nil, "superko" end
    return board, key, captured, liberty
end
function M.Play(s, x, y)
    if s.status ~= "playing" then return false, "finished" end
    local i = Index(x, y)
    if i == nil then return false, "invalid_move" end
    local board, key, captured = Trial(s, i)
    if board == nil then return false, key end
    s.board, s.seen[key], s.last = board, true, i
    s.captures[s.turn] = s.captures[s.turn] + captured
    s.turn, s.count, s.revision, s.passes = 3 - s.turn, s.count + 1, s.revision + 1, 0
    return true
end
function M.BeginScoring(s)
    if s.status ~= "playing" then return false, "forbidden" end
    s.status, s.dead, s.confirmed = "scoring", {}, {false, false}
    s.preview = M.Score(s)
    s.revision = s.revision + 1
    return true
end
function M.Pass(s)
    if s.status ~= "playing" then return false, "forbidden" end
    s.turn, s.passes, s.last = 3 - s.turn, s.passes + 1, nil
    s.revision = s.revision + 1
    if s.passes >= 2 then M.BeginScoring(s) end
    return true
end
function M.Mark(s, x, y)
    local i = Index(x, y)
    if s.status ~= "scoring" or i == nil or s.board[i] == 0 then return false, "invalid_move" end
    local dead = not s.dead[tostring(i)]
    for _, k in ipairs(Group(s.board, i)) do s.dead[tostring(k)] = dead or nil end
    s.confirmed, s.revision = {false, false}, s.revision + 1
    s.preview = M.Score(s)
    return true
end
function M.Score(s)
    local board, totals, visited = Copy(s.board), {0, M.KOMI}, {}
    for key in pairs(s.dead or {}) do board[tonumber(key)] = 0 end
    for i = 1, N * N do
        if board[i] ~= 0 then totals[board[i]] = totals[board[i]] + 1
        elseif not visited[i] then
            local region, borders, cursor = {i}, {}, 1; visited[i] = true
            while cursor <= #region do
                local j = region[cursor]; cursor = cursor + 1
                for _, k in ipairs(neighbors[j]) do
                    if board[k] ~= 0 then borders[board[k]] = true
                    elseif not visited[k] then visited[k] = true; region[#region + 1] = k end
                end
            end
            if borders[1] and not borders[2] then totals[1] = totals[1] + #region
            elseif borders[2] and not borders[1] then totals[2] = totals[2] + #region end
        end
    end
    return totals
end
function M.Confirm(s, side)
    if s.status ~= "scoring" or side ~= 1 and side ~= 2 then return false, "forbidden" end
    s.confirmed[side], s.revision = true, s.revision + 1
    if s.confirmed[1] and s.confirmed[2] then
        s.score = M.Score(s)
        s.winner = s.score[1] > s.score[2] and 1 or 2
        s.status = "won"
    end
    return true
end
function M.Resume(s)
    if s.status ~= "scoring" then return false, "forbidden" end
    s.status, s.dead, s.confirmed, s.passes, s.preview = "playing", nil, nil, 0, nil
    s.revision = s.revision + 1
    return true
end
function M.ChooseMove(s)
    if s.status ~= "playing" or s.passes > 0 then return end
    return require("my_friend_go_ai").ChooseMove(s, neighbors, Trial)
end
return M
