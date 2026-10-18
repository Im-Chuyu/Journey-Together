local lang = require("my_friend_strings").language
local ok, strings = pcall(require, "languages/" .. tostring(lang) .. "/games")
local fallback = require("languages/zh/games")
if not ok or type(strings) ~= "table" then strings = fallback end
local M = {}
function M.Get(key) return strings[key] or fallback[key] or tostring(key) end
function M.Format(key, ...) return string.format(M.Get(key), ...) end
return M
