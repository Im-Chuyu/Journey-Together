package.path = "./scripts/?.lua;" .. package.path
local Go = require("my_friend_go")
local function I(x, y) return (y - 1) * 19 + x end
local function Put(s, side, points) for _, p in ipairs(points) do s.board[I(p[1], p[2])] = side end end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Choose(s)
    local search, slices, maximum = Go.BeginSearch(s), 0, 0
    while true do
        local started = os.clock()
        local done, x, y = search:Step()
        maximum, slices = math.max(maximum, os.clock() - started), slices + 1
        if done then return x, y, search, slices, maximum end
    end
end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("opening remains legal and spreads toward a corner", function()
    local s = Go.New(); local x, y, job, slices = Choose(s)
    assert(Go.Play(s, x, y) and (x == 4 or x == 16) and (y == 4 or y == 16))
    assert(slices > 1 and job.nodes <= 385)
end)
Test("protects three endangered stones instead of blindly capturing one", function()
    local s = Go.New()
    Put(s, 1, {{5, 5}, {5, 6}, {5, 7}, {11, 12}, {12, 11}, {13, 12}})
    Put(s, 2, {{4, 5}, {6, 5}, {4, 6}, {6, 6}, {4, 7}, {6, 7}, {5, 8}, {12, 12}})
    local x, y = Choose(s)
    assert(x == 5 and y == 4, tostring(x) .. "," .. tostring(y))
    assert(Go.Play(s, x, y) and s.captures[1] == 0)
end)
Test("still captures a valuable available group", function()
    local s = Go.New()
    Put(s, 2, {{8, 8}, {8, 9}, {8, 10}})
    Put(s, 1, {{7, 8}, {9, 8}, {7, 9}, {9, 9}, {7, 10}, {9, 10}, {8, 11}})
    local x, y = Choose(s)
    assert(x == 8 and y == 7)
    assert(Go.Play(s, x, y) and s.captures[1] == 3)
end)
Test("an early player pass no longer forces the companion to end the game", function()
    local s = Go.New(); assert(Go.Pass(s))
    local x, y = Go.ChooseMove(s)
    assert(x ~= nil and Go.Play(s, x, y) and s.status == "playing")
end)
Test("does not fill an established corner eye for a quiet move", function()
    local s = Go.New(); Put(s, 1, {{1, 2}, {2, 1}, {2, 2}})
    local x, y = Choose(s)
    assert(x ~= 1 or y ~= 1)
    assert(Go.Play(s, x, y))
end)
Test("search preserves board, history, turn, revision and superko set", function()
    local s = Go.New(); Go.Play(s, 4, 4); Go.Play(s, 16, 16)
    local board, keys, history, revision, turn = table.concat(s.board), Count(s.seen), #s.history, s.revision, s.turn
    local x, y, search = Choose(s)
    assert(table.concat(s.board) == board and Count(s.seen) == keys and #s.history == history)
    assert(s.revision == revision and s.turn == turn and search.nodes <= 385)
    assert(Go.Play(s, x, y))
end)
Test("positional superko is respected by actual trial generation", function()
    local s = Go.New()
    local saved = Go.New(); assert(Go.Play(saved, 4, 4))
    local key; for candidate in pairs(saved.seen) do if not s.seen[candidate] then key = candidate end end
    assert(key); s.seen[key] = true
    local x, y = Choose(s)
    assert(x ~= 4 or y ~= 4)
    assert(Go.Play(s, x, y))
end)
Test("full board has no legal choice and search remains bounded", function()
    local s = Go.New(); for i = 1, 361 do s.board[i] = 1 end
    local x, y, job = Choose(s)
    assert(x == nil and y == nil and job.nodes <= 385)
end)
print(string.format("%d Go AI tests passed", passed))
