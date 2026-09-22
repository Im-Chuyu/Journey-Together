-- Language selection shared by the UI, keyword loader and dialogue loader.
-- Add a language option in modinfo.lua and provide matching *_<code>.lua
-- files; missing dialogue falls back to Chinese.
local M = {language = "zh"}

function M.Text(zh, en)
    return M.language == "en" and en or zh
end

return M
