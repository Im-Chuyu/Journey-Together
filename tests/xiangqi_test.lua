package.path = "./scripts/?.lua;" .. package.path
local R = require("my_friend_xiangqi")
local function I(x, y) return (y - 1) * 9 + x end
local function Position(pieces, turn)
    local s = R.New()
    for i = 1, 90 do s.board[i] = 0 end
    for _, p in ipairs(pieces) do s.board[I(p[1], p[2])] = p[3] end
    s.turn = turn or 1
    return s
end
local function Base(extra)
    local p = {{5, 10, 1}, {5, 1, 8}, {5, 5, 7}}
    for _, v in ipairs(extra or {}) do p[#p + 1] = v end
    return Position(p)
end
local function Legal(s, ax, ay, bx, by) return R.Legal(s.board, s.turn, R.Index(ax, ay), R.Index(bx, by)) end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

Test("initial army has 32 pieces, 44 legal first moves and 1920 two-ply continuations", function()
    local s, count = R.New(), 0
    for _, p in ipairs(s.board) do if p ~= 0 then count = count + 1 end end
    assert(count == 32 and #R.Generate(s.board, 1) == 44)
    local total = 0
    for _, move in ipairs(R.Generate(s.board, 1)) do
        local a, b = math.floor(move / 128), move % 128
        local p = s.board[b]; s.board[b], s.board[a] = s.board[a], 0
        total = total + #R.Generate(s.board, 2)
        s.board[a], s.board[b] = s.board[b], p
    end
    assert(total == 1920, total)
end)
Test("generals stay in their palaces and cannot face each other", function()
    local s = Base()
    assert(Legal(s, 5, 10, 4, 10) and not Legal(s, 5, 10, 5, 7))
    s.board[I(5, 5)] = 5
    assert(not Legal(s, 5, 5, 4, 5))
    s.board[I(5, 5)] = 0
    assert(R.InCheck(s.board, 1) and R.InCheck(s.board, 2))
end)
Test("advisors are diagonal palace pieces", function()
    local s = Base({{4, 10, 2}})
    assert(Legal(s, 4, 10, 5, 9) and not Legal(s, 4, 10, 3, 9) and not Legal(s, 4, 10, 4, 9))
end)
Test("elephants cannot cross the river and blocked eyes prevent jumping", function()
    local s = Base({{3, 10, 3}})
    assert(Legal(s, 3, 10, 1, 8))
    s.board[I(2, 9)] = 7
    assert(not Legal(s, 3, 10, 1, 8))
    s.board[I(3, 10)], s.board[I(3, 6)] = 0, 3
    assert(not Legal(s, 3, 6, 1, 4))
end)
Test("horses have the correct leg for both orientations", function()
    local s = Base({{3, 7, 4}})
    assert(Legal(s, 3, 7, 4, 5) and Legal(s, 3, 7, 5, 6))
    s.board[I(3, 6)] = 7
    assert(not Legal(s, 3, 7, 4, 5) and Legal(s, 3, 7, 5, 6))
    s.board[I(4, 7)] = 7
    assert(not Legal(s, 3, 7, 5, 6))
end)
Test("rooks cannot jump and cannons require exactly one screen for capture", function()
    local s = Base({{1, 7, 5}, {2, 7, 7}, {1, 2, 12}, {3, 8, 6}, {3, 3, 12}})
    assert(Legal(s, 1, 7, 1, 2) and not Legal(s, 1, 7, 3, 7))
    assert(not Legal(s, 3, 8, 3, 3) and Legal(s, 3, 8, 3, 5))
    s.board[I(3, 6)] = 7
    assert(Legal(s, 3, 8, 3, 3) and not Legal(s, 3, 8, 3, 5))
    s.board[I(3, 4)] = 14
    assert(not Legal(s, 3, 8, 3, 3))
end)
Test("soldiers move forward, gain sideways moves across the river and never retreat", function()
    local s = Base({{3, 7, 7}})
    assert(Legal(s, 3, 7, 3, 6) and not Legal(s, 3, 7, 4, 7))
    s.board[I(3, 7)], s.board[I(3, 5)] = 0, 7
    assert(Legal(s, 3, 5, 4, 5) and not Legal(s, 3, 5, 3, 6))
    s.turn = 2; s.board[I(3, 6)] = 14
    assert(Legal(s, 3, 6, 4, 6) and Legal(s, 3, 6, 3, 7) and not Legal(s, 3, 6, 3, 5))
end)
Test("a pinned shield cannot expose its general and failed moves preserve all state", function()
    local s = Base({{5, 7, 5}, {5, 3, 12}})
    s.board[I(5, 5)] = 0
    local key, rev = R.Key(s.board, s.turn), s.revision
    assert(not R.Play(s, 4, 7, 5, 7))
    assert(key == R.Key(s.board, s.turn) and #s.history == 0 and rev == s.revision)
    for _, v in ipairs({0, 10, .5, math.huge}) do assert(not R.Play(s, v, 7, 5, 7)) end
end)
Test("checkmate ends the game and restores the old board on takeback before terminal play", function()
    local s = Position({{5, 1, 8}, {5, 10, 1}, {4, 3, 5}, {6, 3, 5}, {5, 4, 5}})
    assert(R.Play(s, 5, 2, 5, 4))
    assert(s.status == "won" and s.winner == 1 and s.reason == "xiangqi_checkmate")
    assert(not R.Play(s, 4, 1, 5, 1))
end)
Test("stalemate is a loss, not a draw", function()
    local s = Position({{5, 1, 8}, {4, 10, 1}, {4, 3, 5}, {6, 3, 5}, {1, 2, 5}})
    assert(R.Play(s, 2, 2, 1, 2))
    assert(s.status == "won" and s.winner == 1 and not s.check and s.reason == "xiangqi_stalemate")
end)
Test("takeback restores turn, compact board history and increments revision", function()
    local s = R.New(); local initial = R.Key(s.board, s.turn)
    assert(R.Play(s, 1, 6, 1, 7)); assert(R.Play(s, 1, 5, 1, 4))
    assert(s.count == 2 and R.CanUndo(s))
    assert(R.Undo(s, 2) and R.Key(s.board, s.turn) == initial and s.revision == 3 and s.count == 0)
    assert(not R.CanUndo(s))
end)
Test("neutral repeated positions draw and one-sided perpetual check loses", function()
    local s = Base({{1, 10, 5}, {1, 1, 12}})
    for round = 1, 2 do
        assert(R.Play(s, 2, 10, 1, 10)); assert(R.Play(s, 2, 1, 1, 1))
        assert(R.Play(s, 1, 10, 2, 10)); assert(R.Play(s, 1, 1, 2, 1))
    end
    assert(s.status == "draw" and s.reason == "xiangqi_repetition")
    s = Position({{5, 1, 8}, {5, 10, 1}, {5, 5, 7}, {4, 2, 5}})
    for round = 1, 2 do
        assert(R.Play(s, 5, 2, 4, 2)); assert(R.Play(s, 4, 1, 5, 1))
        assert(R.Play(s, 4, 2, 5, 2)); assert(R.Play(s, 5, 1, 4, 1))
    end
    assert(s.status == "won" and s.winner == 2 and s.reason == "xiangqi_perpetual")
end)
Test("quiet counter resets on captures/forward soldiers and capped quiet play draws", function()
    local s = R.New(); s.quiet = 119
    assert(R.Play(s, 1, 6, 1, 7) and s.quiet == 0)
    s = R.New(); s.quiet = 119
    assert(R.Play(s, 3, 8, 2, 10) and s.status == "draw")
end)
Test("bot finds a mating move, returns legal moves and leaves authoritative state untouched", function()
    local s = Position({{5, 1, 8}, {5, 10, 1}, {4, 3, 5}, {6, 3, 5}, {5, 4, 5}})
    local key = R.Key(s.board, s.turn)
    local search = R.BeginSearch(s)
    local x, y, fx, fy
    while true do local done; done, x, y, fx, fy = search:Step(); if done then break end end
    assert(R.Key(s.board, s.turn) == key and #s.history == 0)
    assert(R.Play(s, x, y, fx, fy) and s.status == "won")
    assert(search.nodes <= 10001 and (search.entries or 0) <= 2048)
end)
Test("bot declines a poisoned soldier that would lose a rook", function()
    local s = Base({{1, 6, 5}, {1, 4, 14}, {1, 3, 12}})
    local x, y, fx, fy = R.ChooseMove(s)
    assert(not (fx == 1 and fy == 6 and x == 1 and y == 4))
    assert(R.Play(s, x, y, fx, fy))
end)
Test("legal-move generation is consistent during varied play and full takeback", function()
    local s, initial = R.New(), R.New()
    for ply = 1, 60 do
        if s.status ~= "playing" then break end
        local moves = R.Generate(s.board, s.turn)
        assert(#moves > 0)
        local move = moves[(ply * 17) % #moves + 1]
        local a, b = math.floor(move / 128), move % 128
        local previous = s.turn
        assert(R.Play(s, (b - 1) % 9 + 1, math.floor((b - 1) / 9) + 1,
            (a - 1) % 9 + 1, math.floor((a - 1) / 9) + 1))
        assert(not R.InCheck(s.board, previous))
    end
    if s.status == "playing" then
        assert(R.Undo(s, #s.history) and R.Key(s.board, s.turn) == R.Key(initial.board, initial.turn))
    end
end)
print(string.format("%d Xiangqi tests passed", passed))
