-- Pure Xiangqi rules. Red is seat 1 (bottom, moves first), Black seat 2.
-- Pieces: general/advisor/elephant/horse/rook/cannon/soldier, then +7 for Black.
local M = {SIZE = 9, HEIGHT = 10, CELLS = 90, MAX_COUNT = 1024}
local X, Y = {}, {}
for i = 1, 90 do X[i], Y[i] = (i - 1) % 9 + 1, math.floor((i - 1) / 9) + 1 end
function M.Side(piece) return piece == 0 and 0 or math.floor((piece - 1) / 7) + 1 end
function M.Kind(piece) return (piece - 1) % 7 + 1 end
function M.Index(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x % 1 ~= 0 or y % 1 ~= 0
        or x < 1 or x > 9 or y < 1 or y > 10 then return end
    return (y - 1) * 9 + x
end
function M.Key(board, turn)
    local chars = {}
    for i = 1, 90, 2 do chars[#chars + 1] = string.char(board[i] + board[i + 1] * 16) end
    return table.concat(chars) .. string.char(turn)
end
local function Decode(key)
    local board = {}
    for i = 1, 45 do local b = key:byte(i); board[i * 2 - 1], board[i * 2] = b % 16, math.floor(b / 16) end
    return board
end
local function Palace(side, x, y) return x >= 4 and x <= 6 and (side == 1 and y >= 8 or side == 2 and y <= 3) end
local function Screens(board, a, b)
    local step = X[a] == X[b] and (b > a and 9 or -9) or (b > a and 1 or -1)
    local count = 0
    for i = a + step, b - step, step do if board[i] ~= 0 then count = count + 1 end end
    return count
end
local function Reach(board, a, b)
    local p, target = board[a], board[b]
    if p == 0 or a == b or target ~= 0 and M.Side(target) == M.Side(p) then return false end
    local side, kind = M.Side(p), M.Kind(p)
    local dx, dy = X[b] - X[a], Y[b] - Y[a]
    local ax, ay = math.abs(dx), math.abs(dy)
    if kind == 1 then
        if target ~= 0 and M.Kind(target) == 1 and dx == 0 then return Screens(board, a, b) == 0 end
        return ax + ay == 1 and Palace(side, X[b], Y[b])
    elseif kind == 2 then return ax == 1 and ay == 1 and Palace(side, X[b], Y[b])
    elseif kind == 3 then
        return ax == 2 and ay == 2 and (side == 1 and Y[b] >= 6 or side == 2 and Y[b] <= 5)
            and board[a + dx / 2 + dy / 2 * 9] == 0
    elseif kind == 4 then
        return ax * ay == 2 and ax + ay == 3
            and board[a + (ax == 2 and dx / 2 or dy / 2 * 9)] == 0
    elseif kind == 5 or kind == 6 then
        if dx ~= 0 and dy ~= 0 then return false end
        return Screens(board, a, b) == (kind == 6 and target ~= 0 and 1 or 0)
    elseif kind == 7 then
        return dx == 0 and dy == (side == 1 and -1 or 1)
            or dy == 0 and ax == 1 and (side == 1 and Y[a] <= 5 or side == 2 and Y[a] >= 6)
    end
    return false
end
function M.InCheck(board, side)
    local king
    for i = 1, 90 do if board[i] == (side - 1) * 7 + 1 then king = i; break end end
    if king == nil then return true end
    for i = 1, 90 do if board[i] ~= 0 and M.Side(board[i]) ~= side and Reach(board, i, king) then return true end end
    return false
end
function M.Legal(board, side, a, b)
    if a == nil or b == nil or board[a] == nil or board[b] == nil or board[a] == 0
        or M.Side(board[a]) ~= side or not Reach(board, a, b) then return false end
    local target = board[b]; board[b], board[a] = board[a], 0
    local safe = not M.InCheck(board, side)
    board[a], board[b] = board[b], target
    return safe
end
local DIAGONALS = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
local HORSES = {{1, 2}, {2, 1}, {-1, 2}, {-2, 1}, {1, -2}, {2, -1}, {-1, -2}, {-2, -1}}
local DIRECTIONS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
function M.Generate(board, side, captures, work)
    local moves = {}
    local function Add(a, x, y)
        local b = x >= 1 and x <= 9 and y >= 1 and y <= 10 and (y - 1) * 9 + x or nil
        if b ~= nil and (not captures or board[b] ~= 0) and M.Legal(board, side, a, b) then
            moves[#moves + 1] = a * 128 + b
        end
    end
    for a = 1, 90 do
        if work ~= nil and a % 8 == 0 then work:Pause() end
        if board[a] ~= 0 and M.Side(board[a]) == side then
        local kind, x, y = M.Kind(board[a]), X[a], Y[a]
        if kind == 5 or kind == 6 then
            for _, d in ipairs(DIRECTIONS) do
                local px, py, blocks = x + d[1], y + d[2], 0
                while px >= 1 and px <= 9 and py >= 1 and py <= 10 do
                    Add(a, px, py)
                    if board[(py - 1) * 9 + px] ~= 0 then blocks = blocks + 1 end
                    if blocks >= (kind == 6 and 2 or 1) then break end
                    px, py = px + d[1], py + d[2]
                end
            end
        elseif kind == 4 then for _, d in ipairs(HORSES) do Add(a, x + d[1], y + d[2]) end
        elseif kind == 2 or kind == 3 then
            local step = kind == 3 and 2 or 1
            for _, d in ipairs(DIAGONALS) do Add(a, x + d[1] * step, y + d[2] * step) end
        elseif kind == 7 then
            Add(a, x, y + (side == 1 and -1 or 1)); Add(a, x - 1, y); Add(a, x + 1, y)
        else
            for _, d in ipairs(DIRECTIONS) do Add(a, x + d[1], y + d[2]) end
            for b = 1, 90 do if board[b] ~= 0 and M.Kind(board[b]) == 1 and M.Side(board[b]) ~= side then Add(a, X[b], Y[b]) end end
        end
    end end
    return moves
end
function M.New()
    local board = {}; for i = 1, 90 do board[i] = 0 end
    local row = {5, 4, 3, 2, 1, 2, 3, 4, 5}
    for x = 1, 9 do board[x], board[81 + x] = row[x] + 7, row[x] end
    board[20], board[26], board[65], board[71] = 13, 13, 6, 6
    for x = 1, 9, 2 do board[27 + x], board[54 + x] = 14, 7 end
    return {board = board, turn = 1, status = "playing", count = 0, revision = 0,
        history = {}, quiet = 0, check = false}
end
function M.CanUndo(s) return s.status == "playing" and #s.history > 0 end
function M.Play(s, x, y, from_x, from_y)
    if s.status ~= "playing" then return false, "finished" end
    local a, b = M.Index(from_x, from_y), M.Index(x, y)
    if not M.Legal(s.board, s.turn, a, b) then return false, "xiangqi_illegal" end
    local key, captured, piece = M.Key(s.board, s.turn), s.board[b], s.board[a]
    s.history[#s.history + 1] = {key = key, quiet = s.quiet, last = s.last, last_from = s.last_from, check = s.check}
    s.board[b], s.board[a], s.last_from, s.last = piece, 0, a, b
    if captured ~= 0 or M.Kind(piece) == 7 and Y[a] ~= Y[b] then s.quiet = 0 else s.quiet = s.quiet + 1 end
    local mover = s.turn
    s.turn, s.count, s.revision = 3 - s.turn, s.count + 1, s.revision + 1
    s.check = M.InCheck(s.board, s.turn)
    s.history[#s.history].gave_check = s.check
    if captured ~= 0 and M.Kind(captured) == 1 or #M.Generate(s.board, s.turn) == 0 then
        s.status, s.winner = "won", mover
        s.reason = s.check and "xiangqi_checkmate" or "xiangqi_stalemate"
    else
        local current, repeats, cycle_start = M.Key(s.board, s.turn), 1
        for i = #s.history, 1, -1 do if s.history[i].key == current then
            repeats = repeats + 1; cycle_start = i
            if repeats >= 3 then break end
        end end
        if repeats >= 3 then
            local always = {true, true}
            for i = cycle_start, #s.history do
                local side = s.history[i].key:byte(46)
                if not s.history[i].gave_check then always[side] = false end
            end
            if always[1] ~= always[2] then
                s.status, s.winner, s.reason = "won", always[1] and 2 or 1, "xiangqi_perpetual"
            else s.status, s.reason = "draw", "xiangqi_repetition" end
        elseif s.quiet >= 120 or s.count >= M.MAX_COUNT then
            s.status, s.reason = "draw", "xiangqi_move_limit"
        end
    end
    return true
end
function M.Undo(s, plies)
    if not M.CanUndo(s) then return false, "undo_unavailable" end
    local index = math.max(1, #s.history - math.max(1, math.floor(plies or 1)) + 1)
    local entry = s.history[index]
    s.board, s.turn, s.quiet, s.last, s.last_from, s.check = Decode(entry.key), entry.key:byte(46),
        entry.quiet, entry.last, entry.last_from, entry.check
    s.count, s.revision = index - 1, s.revision + 1
    s.status, s.winner, s.reason = "playing", nil, nil
    for i = #s.history, index, -1 do s.history[i] = nil end
    return true
end
function M.BeginSearch(s) return require("my_friend_xiangqi_ai").BeginSearch(s, M) end
function M.ChooseMove(s)
    if s.status ~= "playing" then return end
    local search = M.BeginSearch(s)
    while true do local done, x, y, fx, fy = search:Step(); if done then return x, y, fx, fy end end
end
return M
