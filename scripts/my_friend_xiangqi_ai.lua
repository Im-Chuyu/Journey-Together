-- Original lightweight alpha-beta search: iterative deepening, capture ordering,
-- quiescence and a per-turn capped transposition table. No engine/model dependency.
local Search = require("my_friend_board_search")
local M = {NODE_LIMIT = 10000, TABLE_LIMIT = 2048, MAX_DEPTH = 4}
local VALUE = {20000, 120, 120, 300, 650, 350, 70}
local function Evaluate(board, side, rules)
    local value = 0
    for i = 1, 90 do if board[i] ~= 0 then
        local owner, kind = rules.Side(board[i]), rules.Kind(board[i])
        local x, y = (i - 1) % 9 + 1, math.floor((i - 1) / 9) + 1
        local advance = owner == 1 and 10 - y or y - 1
        local central = 4 - math.abs(x - 5)
        local bonus = kind == 7 and (advance * 5 + (advance >= 5 and 45 + central * 4 or 0))
            or kind == 4 and central * 7 + math.min(advance, 5) * 3
            or kind == 5 and central * 2 + math.min(advance, 6) * 2
            or kind == 6 and central * 4 or 0
        value = value + (owner == side and 1 or -1) * (VALUE[kind] + bonus)
    end end
    return value
end
function M.BeginSearch(state, rules)
    local board, side = {}, state.turn
    for i = 1, 90 do board[i] = state.board[i] end
    return Search.New(function(work)
        local tt, path, entries = {}, {}, 0
        local function Order(moves, preferred)
            local scores = {}
            for _, move in ipairs(moves) do
                local a, b = math.floor(move / 128), move % 128
                scores[move] = move == preferred and 1000000 or board[b] ~= 0
                    and VALUE[rules.Kind(board[b])] * 16 - VALUE[rules.Kind(board[a])] or 0
            end
            table.sort(moves, function(a, b) return scores[a] == scores[b] and a < b or scores[a] > scores[b] end)
        end
        local function Make(move)
            local a, b = math.floor(move / 128), move % 128
            local captured = board[b]; board[b], board[a] = board[a], 0
            return a, b, captured
        end
        local function Unmake(a, b, captured) board[a], board[b] = board[b], captured end
        local AlphaBeta
        AlphaBeta = function(turn, depth, alpha, beta, ply, quiet)
            if not work:Visit() then return Evaluate(board, turn, rules) end
            local key = rules.Key(board, turn)
            if path[key] then return 0 end
            local original, cached = alpha, depth > 0 and tt[key] or nil
            if cached ~= nil and cached.depth >= depth then
                if cached.flag == 0 then return cached.score end
                if cached.flag == 1 then alpha = math.max(alpha, cached.score) else beta = math.min(beta, cached.score) end
                if alpha >= beta then return cached.score end
            end
            local check = rules.InCheck(board, turn)
            local stand = Evaluate(board, turn, rules)
            if depth <= 0 and not check then
                if stand >= beta then return stand end
                alpha = math.max(alpha, stand)
                if quiet >= 3 then return stand end
            elseif depth <= -4 then return stand end
            local moves = rules.Generate(board, turn, depth <= 0 and not check, work)
            if #moves == 0 then return (depth > 0 or check) and -100000 + ply or stand end
            Order(moves, cached ~= nil and cached.move or nil)
            path[key] = true
            local best, bestmove = depth <= 0 and not check and stand or -100001, nil
            for _, move in ipairs(moves) do
                local a, b, captured = Make(move)
                local score = -AlphaBeta(3 - turn, depth - 1, -beta, -alpha, ply + 1, depth <= 0 and quiet + 1 or 0)
                Unmake(a, b, captured)
                if score > best then best, bestmove = score, move end
                alpha = math.max(alpha, score)
                if alpha >= beta or work.exhausted then break end
            end
            path[key] = nil
            if depth > 0 and not work.exhausted and (tt[key] ~= nil or entries < M.TABLE_LIMIT) then
                if tt[key] == nil then entries = entries + 1 end
                tt[key] = {depth = depth, score = best, move = bestmove,
                    flag = best <= original and 2 or best >= beta and 1 or 0}
                work.entries = entries
            end
            return best
        end
        local moves = rules.Generate(board, side, false, work)
        if #moves == 0 then return end
        Order(moves)
        local chosen = moves[1]
        for depth = 1, M.MAX_DEPTH do
            Order(moves, chosen)
            local best, bestscore = chosen, -100001
            for _, move in ipairs(moves) do
                local a, b, captured = Make(move)
                local score = -AlphaBeta(3 - side, depth - 1, -100001, -bestscore, 1, 0)
                Unmake(a, b, captured)
                if work.exhausted then break end
                if score > bestscore then best, bestscore = move, score end
            end
            if work.exhausted then break end
            chosen, work.completed_depth = best, depth
            if bestscore > 99900 then break end
        end
        local a, b = math.floor(chosen / 128), chosen % 128
        return (b - 1) % 9 + 1, math.floor((b - 1) / 9) + 1,
            (a - 1) % 9 + 1, math.floor((a - 1) / 9) + 1
    end, M.NODE_LIMIT)
end
return M
