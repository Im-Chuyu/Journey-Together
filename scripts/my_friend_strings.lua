-- Language helper only. Every player facing line lives in
-- my_friend_dialogue_lines.lua, which is the file to edit when rewriting
-- the companion's dialogue.
local M = {language = "zh"}

function M.Text(zh, en)
    return M.language == "en" and en or zh
end

return M
