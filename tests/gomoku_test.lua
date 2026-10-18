package.path = "scripts/?.lua;" .. package.path
local Rules = require("my_friend_gomoku")
local function index(x, y) return (y - 1) * 15 + x end
local s = Rules.New()
for _, p in ipairs({{0, 1}, {16, 1}, {1.5, 2}, {"1", 1}, {0/0, 1}, {1/0, 1}}) do
    assert(not Rules.Play(s, p[1], p[2]))
    assert(s.count == 0 and s.revision == 0)
end
assert(Rules.Play(s, 8, 8))
assert(not Rules.Play(s, 8, 8) and s.turn == 2 and s.count == 1)
for _, direction in ipairs({{1, 0}, {0, 1}, {1, 1}, {1, -1}}) do
    local game = Rules.New()
    for n = 0, 3 do
        local x, y = 3 + n * direction[1], 8 + n * direction[2]
        game.board[index(x, y)] = 1; game.count = game.count + 1
    end
    assert(Rules.Play(game, 3 + 4 * direction[1], 8 + 4 * direction[2]))
    assert(game.status == "won" and game.winner == 1 and #game.line == 5)
    assert(not Rules.Play(game, 15, 15), "finished games cannot accept another move")
end
s = Rules.New()
for _, x in ipairs({2, 3, 4, 6, 7}) do s.board[index(x, 8)] = 1; s.count = s.count + 1 end
assert(Rules.Play(s, 5, 8) and s.winner == 1 and #s.line == 6, "overlines are wins")
s = Rules.New()
for y = 1, 15 do for x = 1, 15 do s.board[index(x, y)] = (x + 2 * y) % 4 < 2 and 1 or 2 end end
s.count, s.turn = 224, s.board[225]; s.board[225] = 0
assert(Rules.Play(s, 15, 15) and s.status == "draw")
s = Rules.New(); local x, y = Rules.ChooseMove(s)
assert(x == 8 and y == 8 and s.count == 0)
for i = 1, 4 do s.board[index(i, 3)] = 2 end
s.count = 4
x, y = Rules.ChooseMove(s)
assert(x == 5 and y == 3, "companion blocks an immediate five")
for i = 1, 4 do s.board[index(i, 7)] = 1 end
s.count = 8
local before = table.concat(s.board, ",")
x, y = Rules.ChooseMove(s)
assert(x == 5 and y == 7, "an immediate win takes precedence over blocking")
assert(table.concat(s.board, ",") == before and s.revision == 0, "analysis must leave the board unchanged")
-- Exercise complete legal games without a recursive/minimax search budget.
for _ = 1, 3 do
    s = Rules.New()
    while s.status == "playing" do
        x, y = Rules.ChooseMove(s)
        assert(x ~= nil and Rules.Play(s, x, y))
        assert(s.count <= 225)
    end
end
print("PASS: Gomoku bounds/NaN/duplicates, four win directions, overlines, draw, immediate win/block and bounded complete AI games")
