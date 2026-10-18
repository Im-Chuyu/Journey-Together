package.path = "scripts/?.lua;" .. package.path
local Go = require("my_friend_go")
local function at(x, y) return (y - 1) * 19 + x end
local function move(s, x, y) assert(Go.Play(s, x, y)) end
local s = Go.New()
assert(#s.board == 361 and s.turn == 1)
for _, point in ipairs({{0, 1}, {20, 1}, {1.5, 1}, {0/0, 1}, {math.huge, 1}, {1, -math.huge}}) do
    assert(not Go.Play(s, point[1], point[2]))
end
assert(not Go.Play(s, "1", 1))
move(s, 1, 1); assert(not Go.Play(s, 1, 1))
-- A corner capture, followed by a forbidden suicide.
move(s, 2, 1); move(s, 10, 10); move(s, 1, 2)
assert(s.board[1] == 0 and s.captures[2] == 1)
local revision = s.revision
local ok, reason = Go.Play(s, 1, 1)
assert(not ok and reason == "suicide" and s.revision == revision and s.board[1] == 0)
-- Exact positional superko, including after passing and resuming.
s = Go.New()
for _, p in ipairs({{1,2},{2,2},{2,1},{3,1},{2,3},{4,2},{10,10},{3,3},{3,2}}) do move(s,p[1],p[2]) end
assert(s.board[at(2,2)] == 0 and s.captures[1] == 1)
ok, reason = Go.Play(s, 2, 2); assert(not ok and reason == "superko")
Go.Pass(s); Go.Pass(s); assert(s.status == "scoring")
assert(Go.Resume(s)); assert(s.turn == 2)
ok, reason = Go.Play(s, 2, 2); assert(not ok and reason == "superko")
-- Several stones of one group are removed together, with capture-before-
-- suicide: taking the opponent creates the move's liberties.
s = Go.New()
s.board[at(1,1)], s.board[at(1,2)] = 2, 2
s.board[at(2,1)], s.board[at(2,2)] = 1, 1
move(s,1,3); assert(s.captures[1] == 2 and s.board[1] == 0 and s.board[20] == 0)
-- Area scoring: a wall divides the board into disjoint regions.
s = Go.New()
for y = 1,19 do s.board[at(9,y)], s.board[at(11,y)] = 1,2 end
Go.BeginScoring(s)
local score = Go.Score(s)
assert(score[1] == 171 and score[2] == 178.5, "shared dame must not count for either side")
assert(Go.Confirm(s,1) and s.status == "scoring")
assert(Go.Mark(s,9,1) and not s.confirmed[1])
for y = 1,19 do assert(s.dead[tostring(at(9,y))]) end
assert(Go.Mark(s,9,19) and next(s.dead) == nil)
assert(Go.Confirm(s,2) and s.status == "scoring")
assert(Go.Confirm(s,1) and s.status == "won" and s.winner == 2 and s.score[1] == 171)
assert(not Go.Play(s,1,1) and not Go.Mark(s,9,1))
-- Empty boards are neutral; komi alone goes to White.
s = Go.New(); Go.Pass(s); Go.Pass(s)
score = Go.Score(s); assert(score[1] == 0 and score[2] == 7.5)
assert(Go.Resume(s) and s.passes == 0 and s.dead == nil)
local start = os.clock()
for i = 1, 30 do
    local x,y = Go.ChooseMove(s); assert(x ~= nil); move(s,x,y)
end
assert(os.clock() - start < 8, "the basic bot must use bounded work")
Go.Pass(s); assert(Go.ChooseMove(s) == nil, "the bot agrees to pass after the human passes")
-- The bounded tactical search should notice an immediate capture instead of
-- choosing an unrelated opening point.
s = Go.New()
s.board[at(1, 1)], s.board[at(2, 2)], s.board[at(1, 2)] = 1, 1, 2
s.seen = {}
local x, y = Go.ChooseMove(s)
assert(x == 1 and y == 3, "the bot should take an available capture")
-- A group with one liberty should be connected/rescued before quiet play.
s = Go.New()
s.board[at(8, 10)], s.board[at(9, 10)], s.board[at(10, 10)] = 1, 1, 1
s.board[at(8, 9)], s.board[at(9, 9)], s.board[at(10, 9)] = 2, 2, 2
s.board[at(8, 11)], s.board[at(9, 11)], s.board[at(10, 11)] = 2, 2, 2
s.board[at(7, 10)] = 2
x, y = Go.ChooseMove(s)
assert(x == 11 and y == 10, "the bot should save a group with one liberty")
print("PASS: 19x19 Go capture, liberties/suicide, exact superko, passes/resumption, agreed dead groups, area/komi and bounded legal bot")
