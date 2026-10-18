-- Pure rules and a bounded, event-driven companion opponent. No world state.
local M = {SIZE = 15}
local DIRECTIONS = {{1, 0}, {0, 1}, {1, 1}, {1, -1}}
local function Inside(x, y) return x >= 1 and x <= M.SIZE and y >= 1 and y <= M.SIZE end
local function Index(x, y) return (y - 1) * M.SIZE + x end
local function Integer(n) return type(n) == "number" and n == n and n % 1 == 0 end
function M.New()
    local board = {}
    for i = 1, M.SIZE * M.SIZE do board[i] = 0 end
    return {board = board, turn = 1, count = 0, revision = 0, status = "playing"}
end
local function Line(board, x, y, side, dx, dy)
    local count, open, cells = 1, 0, {Index(x, y)}
    for _, sign in ipairs({-1, 1}) do
        local px, py = x + dx * sign, y + dy * sign
        while Inside(px, py) and board[Index(px, py)] == side do
            count = count + 1; cells[#cells + 1] = Index(px, py)
            px, py = px + dx * sign, py + dy * sign
        end
        if Inside(px, py) and board[Index(px, py)] == 0 then open = open + 1 end
    end
    return count, open, cells
end
function M.Play(state, x, y)
    if state.status ~= "playing" then return false, "finished" end
    if not Integer(x) or not Integer(y) or not Inside(x, y) then return false, "invalid_move" end
    local index = Index(x, y)
    if state.board[index] ~= 0 then return false, "occupied" end
    local side = state.turn
    state.board[index], state.count, state.revision, state.last = side, state.count + 1, state.revision + 1, index
    for _, dir in ipairs(DIRECTIONS) do
        local count, _, cells = Line(state.board, x, y, side, dir[1], dir[2])
        if count >= 5 then state.status, state.winner, state.line = "won", side, cells; return true end
    end
    if state.count == M.SIZE * M.SIZE then state.status = "draw"
    else state.turn = 3 - side end
    return true
end
local function Value(board, x, y, side)
    board[Index(x, y)] = side
    local total, win = 0, false
    for _, dir in ipairs(DIRECTIONS) do
        local n, open = Line(board, x, y, side, dir[1], dir[2])
        if n >= 5 then win = true end
        if open > 0 then total = total + (n >= 4 and 12000 or n == 3 and 900 or n == 2 and 70 or 5) * open end
    end
    board[Index(x, y)] = 0
    return total, win
end
function M.ChooseMove(state)
    if state.status ~= "playing" then return end
    if state.count == 0 then return 8, 8 end
    local candidates = {}
    for y = 1, M.SIZE do for x = 1, M.SIZE do
        if state.board[Index(x, y)] ~= 0 then
            for dy = -2, 2 do for dx = -2, 2 do
                local px, py = x + dx, y + dy
                if Inside(px, py) and state.board[Index(px, py)] == 0 then candidates[Index(px, py)] = true end
            end end
        end
    end end
    local best, score
    for i = 1, M.SIZE * M.SIZE do if candidates[i] then
        local x, y = (i - 1) % M.SIZE + 1, math.floor((i - 1) / M.SIZE) + 1
        local attack, win = Value(state.board, x, y, state.turn)
        local defence, danger = Value(state.board, x, y, 3 - state.turn)
        local value = (win and 100000000 or danger and 10000000 or 0)
            + attack + defence * 1.1 - ((x - 8)^2 + (y - 8)^2) * .01
        if score == nil or value > score then best, score = i, value end
    end end
    if best ~= nil then return (best - 1) % M.SIZE + 1, math.floor((best - 1) / M.SIZE) + 1 end
end
return M
