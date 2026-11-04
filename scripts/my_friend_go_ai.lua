-- Loaded only for an actual companion turn. No tasks, retained search tree,
-- world access or mutation of the authoritative board/history.
local M = {}
local N, POINTS = 19, 361
-- The small fixed beam keeps tactical look-ahead useful while bounding
-- temporary boards. Nothing is retained between turns.
local ROOT_LIMIT, BRANCH_LIMIT, REPLY_LIMIT, FOLLOW_LIMIT = 32, 8, 7, 4
local Search = require("my_friend_board_search")
M.NODE_LIMIT = 384
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
local function Analyze(board, neighbors, work)
    local map, groups = {}, {}
    for i = 1, POINTS do
        if work ~= nil and i % 48 == 0 then work:Pause() end
        if board[i] ~= 0 and map[i] == nil then
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
        local g
        -- The first adjacent intersection may itself be empty. Find any
        -- bordering stone group before checking whether every neighbour
        -- belongs to that same group; this keeps eye scoring accurate without
        -- adding a search branch.
        for _, j in ipairs(neighbors[i]) do
            if map[j] ~= nil then g = map[j]; break end
        end
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
        -- A threatened group is worth less, but never a negative asset: a
        -- negative value would reward leaving enemy stones uncaptured.
        if g.count == 1 then score = math.max(0, score - size * 9 - 4)
        elseif g.count == 2 then score = math.max(0, score - size * 4 - 4) end
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
-- Approximate local influence alongside group safety. This is a position
-- evaluation, not the authoritative agreed-dead-stone area score.
local function Evaluate(board, side, neighbors, work)
    local map, value = Analyze(board, neighbors, work)
    local influence = 0
    for i = 1, POINTS do if board[i] == 0 then
        local own, enemy = 0, 0
        for _, j in ipairs(neighbors[i]) do
            if board[j] == side then own = own + 2 elseif board[j] ~= 0 then enemy = enemy + 2 end
            for _, k in ipairs(neighbors[j]) do
                if board[k] == side then own = own + .25 elseif board[k] ~= 0 then enemy = enemy + .25 end
            end
        end
        influence = influence + math.max(-1, math.min(1, own - enemy)) * 1.5
    end end
    return value[side] - value[3 - side] + influence, map
end
function M.BeginSearch(s, neighbors, trial)
    local board, side, count, passes, historical = {}, s.turn, s.count, s.passes, s.seen
    for i = 1, POINTS do board[i] = s.board[i] end
    return Search.New(function(work)
        -- Overlay branch keys rather than copying or mutating real superko history.
        local seen = setmetatable({}, {__index = historical})
        local initial, map = Evaluate(board, side, neighbors, work)
        local state = {board = board, turn = side, seen = seen}
        local candidates = Candidates(board, side, map, neighbors, ROOT_LIMIT)
        local branches = {}
        for _, c in ipairs(candidates) do
            if not work:Visit() then break end
            local nextboard, key = trial(state, c.i)
            if nextboard ~= nil then
                local value = Evaluate(nextboard, side, neighbors, work)
                c.value, c.score = value, value + c.prior * .08
                local position = #branches + 1
                while position > 1 and branches[position - 1].score < c.score do position = position - 1 end
                if position <= BRANCH_LIMIT then
                    c.board, c.key = nextboard, key
                    table.insert(branches, position, c)
                    if #branches > BRANCH_LIMIT then table.remove(branches) end
                end
            end
        end
        candidates, map = nil, nil
        local best, bestscore, bestprior
        for _, c in ipairs(branches) do
            seen[c.key] = true
            local replymap = Analyze(c.board, neighbors, work)
            local replies = Candidates(c.board, 3 - side, replymap, neighbors, REPLY_LIMIT)
            local replystate = {board = c.board, turn = 3 - side, seen = seen}
            local worst = c.value -- opponent may pass
            for _, reply in ipairs(replies) do
                if not work:Visit() then break end
                local replyboard, replykey = trial(replystate, reply.i)
                if replyboard ~= nil then
                    seen[replykey] = true
                    local replyvalue, followmap = Evaluate(replyboard, side, neighbors, work)
                    local follows = Candidates(replyboard, side, followmap, neighbors, FOLLOW_LIMIT)
                    local followstate = {board = replyboard, turn = side, seen = seen}
                    local response = replyvalue -- we may pass
                    for _, follow in ipairs(follows) do
                        if not work:Visit() then break end
                        local followboard = trial(followstate, follow.i)
                        if followboard ~= nil then response = math.max(response, (Evaluate(followboard, side, neighbors, work))) end
                    end
                    seen[replykey] = nil
                    worst = math.min(worst, response)
                    if bestscore ~= nil and worst + c.prior * .08 < bestscore then break end
                end
            end
            seen[c.key] = nil
            local score = worst + c.prior * .08
            if best == nil or score > bestscore then best, bestscore, bestprior = c.i, score, c.prior end
            if work.exhausted then break end
        end
        -- An early opponent pass is not an order to finish a still-open board.
        if best ~= nil and not (passes > 0 and count >= 120 and bestprior < 55 and bestscore <= initial + 3) then
            return (best - 1) % N + 1, math.floor((best - 1) / N) + 1
        end
    end, M.NODE_LIMIT)
end
function M.ChooseMove(s, neighbors, trial)
    local search = M.BeginSearch(s, neighbors, trial)
    while true do local done, x, y = search:Step(); if done then return x, y end end
end
return M
