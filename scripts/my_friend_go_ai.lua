-- Loaded only for an actual companion turn. No tasks, retained search tree,
-- world access or mutation of the authoritative board/history.
local M = {}
local N, POINTS = 19, 361
-- The small fixed beam keeps tactical look-ahead useful while bounding
-- temporary boards. Nothing is retained between turns.
local ROOT_LIMIT, BRANCH_LIMIT, REPLY_LIMIT = 12, 4, 3
local function Eye(board, i, side, neighbors)
    for _, j in ipairs(neighbors[i]) do if board[j] ~= side then return false end end
    local x, y = (i - 1) % N + 1, math.floor((i - 1) / N) + 1
    local hostile, diagonals = 0, 0
    for dx = -1, 1, 2 do for dy = -1, 1, 2 do
        if x + dx >= 1 and x + dx <= N and y + dy >= 1 and y + dy <= N then
            diagonals = diagonals + 1
            if board[i + dx + dy * N] ~= side then hostile = hostile + 1 end
        end
    end end
    return hostile <= (diagonals == 4 and 1 or 0)
end
local function Analyze(board, neighbors)
    local map, groups = {}, {}
    for i = 1, POINTS do if board[i] ~= 0 and map[i] == nil then
        local g = {side = board[i], stones = {i}, liberties = {}, count = 0, eyes = 0}
        groups[#groups + 1], map[i] = g, g
        local cursor = 1
        while cursor <= #g.stones do
            local j = g.stones[cursor]; cursor = cursor + 1
            for _, k in ipairs(neighbors[j]) do
                if board[k] == 0 and not g.liberties[k] then
                    g.liberties[k], g.count = true, g.count + 1
                elseif board[k] == g.side and map[k] == nil then
                    map[k] = g; g.stones[#g.stones + 1] = k
                end
            end
        end
    end end
    for i = 1, POINTS do if board[i] == 0 then
        local g = map[neighbors[i][1]]
        if g ~= nil and Eye(board, i, g.side, neighbors) then
            local same = true
            for _, j in ipairs(neighbors[i]) do if map[j] ~= g then same = false; break end end
            if same then g.eyes = g.eyes + 1 end
        end
    end end
    local value = {0, 0}
    for _, g in ipairs(groups) do
        local size = #g.stones
        local score = size * 12
        if g.count == 1 then score = score - size * 15 - 12
        elseif g.count == 2 then score = score - size * 3 - 4 end
        if g.eyes >= 2 then score = score + size * 5 + 16
        elseif g.eyes == 1 then score = score + 5 end
        value[g.side] = value[g.side] + score
    end
    return map, value
end
local function Candidates(board, side, map, neighbors, limit)
    local list = {}
    for i = 1, POINTS do if board[i] == 0 then
        local touched, own, enemy, capture, rescue = {}, 0, 0, 0, 0
        local score = 0
        for _, j in ipairs(neighbors[i]) do
            local g = map[j]
            if g ~= nil and not touched[g] then
                touched[g] = true
                if g.side == side then
                    own = own + 1
                    if g.count == 1 then rescue = rescue + #g.stones
                    elseif g.count == 2 then score = score + 7 + #g.stones end
                else
                    enemy = enemy + 1
                    if g.count == 1 then capture = capture + #g.stones
                    elseif g.count == 2 then score = score + 10 + #g.stones * 2 end
                end
            end
        end
        if capture > 0 or rescue > 0 or not Eye(board, i, side, neighbors) then
            score = score + capture * 40 + rescue * 35
                + math.max(0, own - 1) * 12 + math.max(0, enemy - 1) * 9
            if capture > 0 then score = score + 60 end
            if rescue > 0 then score = score + 55 end
            local x, y = (i - 1) % N + 1, math.floor((i - 1) / N) + 1
            local edge = math.min(x, y, N + 1 - x, N + 1 - y)
            score = score + (edge == 1 and -18 or edge == 2 and -6 or edge <= 4 and 7 or 0)
            -- Prefer open corners/third-fourth lines, then approach existing
            -- play. Nearby friendly stones reduce redundant overconcentration.
            local corner = math.min(math.abs(x - 4), math.abs(x - 16))
                + math.min(math.abs(y - 4), math.abs(y - 16))
            score = score + math.max(0, 20 - corner * 3)
            for dy = -3, 3 do for dx = -3, 3 do
                local distance = math.abs(dx) + math.abs(dy)
                if distance > 0 and distance <= 3 and x + dx >= 1 and x + dx <= N and y + dy >= 1 and y + dy <= N then
                    local stone = board[i + dx + dy * N]
                    if stone == side then score = score - (4 - distance) * 2
                    elseif stone ~= 0 then score = score + (4 - distance) end
                end
            end end
            local candidate = {i = i, prior = score}
            -- Fixed-size sorted shortlist; do not retain 361 candidate records.
            local position = #list + 1
            while position > 1 and list[position - 1].prior < score do position = position - 1 end
            if position <= limit then
                table.insert(list, position, candidate)
                if #list > limit then table.remove(list) end
            end
        end
    end end
    return list
end
function M.ChooseMove(s, neighbors, trial)
    local map = Analyze(s.board, neighbors)
    -- Tactical safety comes before positional scoring. A direct capture or a
    -- legal connection that saves a one-liberty group is always more valuable
    -- than a quiet opening point.
    local capture_move, capture_count, rescue_move, rescue_count = nil, 0, nil, 0
    for i = 1, POINTS do if s.board[i] == 0 then
        local groups = {}
        for _, j in ipairs(neighbors[i]) do
            local g = map[j]
            if g ~= nil and not groups[g] then
                groups[g] = true
                if g.side ~= s.turn and g.count == 1 then
                    local board = trial(s, i)
                    if board ~= nil and #g.stones > capture_count then capture_move, capture_count = i, #g.stones end
                elseif g.side == s.turn and g.count == 1 then
                    local board = trial(s, i)
                    if board ~= nil and #g.stones > rescue_count then rescue_move, rescue_count = i, #g.stones end
                end
            end
        end
    end end
    local tactical = capture_move or rescue_move
    if tactical ~= nil then return (tactical - 1) % N + 1, math.floor((tactical - 1) / N) + 1 end
    local candidates = Candidates(s.board, s.turn, map, neighbors, ROOT_LIMIT)
    local branches = {}
    for _, c in ipairs(candidates) do
        local board, key = trial(s, c.i)
        if board ~= nil then
            local _, value = Analyze(board, neighbors)
            c.board, c.key = board, key
            c.value = value[s.turn] - value[3 - s.turn]
            c.score = c.value + c.prior * .08
            local position = #branches + 1
            while position > 1 and branches[position - 1].score < c.score do position = position - 1 end
            if position <= BRANCH_LIMIT then
                table.insert(branches, position, c)
                if #branches > BRANCH_LIMIT then table.remove(branches) end
            end
        end
    end
    -- Drop the root shortlist's references to rejected trial boards now.
    candidates, map = nil, nil
    local best, bestscore
    for _, c in ipairs(branches) do
        local replymap = Analyze(c.board, neighbors)
        local replies = Candidates(c.board, 3 - s.turn, replymap, neighbors, REPLY_LIMIT)
        local replystate = {board = c.board, turn = 3 - s.turn, seen = s.seen}
        local worst = c.value -- the opponent may also pass
        for _, reply in ipairs(replies) do
            local board, key = trial(replystate, reply.i)
            if board ~= nil and key ~= c.key then
                local _, value = Analyze(board, neighbors)
                worst = math.min(worst, value[s.turn] - value[3 - s.turn])
            end
        end
        local score = worst + c.prior * .08
        if best == nil or score > bestscore then best, bestscore = c.i, score end
    end
    if best ~= nil then return (best - 1) % N + 1, math.floor((best - 1) / N) + 1 end
end
return M
