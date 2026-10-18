-- Stable ids and rules interfaces shared by the server and game picker.
-- Future games register here and supply their own board renderer/rules.
local M = {}
M.ORDER = {"gomoku", "go"}
M.GAMES = {gomoku = {id = "gomoku", name = "gomoku", rules = require("my_friend_gomoku"),
    renderer = "widgets/my_friend_gomoku_board", rules_text = "rules"},
    go = {id = "go", name = "go", rules = require("my_friend_go"),
        renderer = "widgets/my_friend_go_board", rules_text = "go_rules"}}
function M.Get(id) return type(id) == "string" and M.GAMES[id] or nil end
return M
