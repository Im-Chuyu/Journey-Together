-- Language selection shared by the UI, keyword loader and dialogue loader.
-- Add a language option in modinfo.lua and provide matching *_<code>.lua
-- files; missing dialogue falls back to Chinese.
local M = {language = "zh"}

function M.Text(zh, en, ru)
    if M.language == "en" then return en end
    if M.language == "ru" then return ru or en or zh end
    return zh
end

local ENGLISH_NAMES = {
    wilson = "Wilson", willow = "Willow", wolfgang = "Wolfgang", wendy = "Wendy",
    wx78 = "WX-78", wickerbottom = "Wickerbottom", woodie = "Woodie", wes = "Wes",
    waxwell = "Maxwell", wathgrithr = "Wigfrid", webber = "Webber", winona = "Winona",
    warly = "Warly", walter = "Walter", wortox = "Wortox", wormwood = "Wormwood",
    wurt = "Wurt", wanda = "Wanda", wonkey = "Wonkey",
}

function M.CompanionName(friend)
    local named = friend.replica ~= nil and friend.replica.named or nil
    -- The named replica is available on clients too; the server-only custom
    -- name field cannot tell a remote panel whether the player renamed us.
    if M.language ~= "en" or friend._my_friend_custom_name ~= nil
        or named ~= nil and named._name:value() ~= "" then
        return friend:GetDisplayName()
    end
    local prefab = friend.prefab or ""
    local translated = LanguageTranslator ~= nil
        and LanguageTranslator:GetTranslatedString("STRINGS.NAMES." .. prefab:upper(), "en") or nil
    return translated or ENGLISH_NAMES[prefab] or friend:GetDisplayName()
end

return M
