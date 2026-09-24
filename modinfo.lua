local simplified_chinese = locale == "zh" or locale == "zhr"
local traditional_chinese = locale == "zht" or locale == "zh_tw" or locale == "zh-tw"
local chinese = simplified_chinese or traditional_chinese
name = chinese and "一路同行" or "Journey Together"
description = simplified_chinese and "在这片永恒大陆，我会与你并肩同行。"
    or traditional_chinese and "在這片永恆大陸，我會與你並肩同行。"
    or "On this eternal continent, I will travel with you."
author = "阮秀"
version = "1.7.2"
forumthread = ""
api_version = 10

dst_compatible = true
all_clients_require_mod = true
client_only_mod = false
server_filter_tags = {"companion", "伙伴"}

icon_atlas = "friend.xml"
icon = "friend.tex"

configuration_options = {
    {
        name = "language",
        label = simplified_chinese and "伙伴语言"
            or traditional_chinese and "夥伴語言"
            or "Companion Language",
        options = {
            -- Add a new {description = "...", data = "xx"} entry after the
            -- reviewed files are added under scripts/languages/xx/.
            {description = simplified_chinese and "中文"
                or traditional_chinese and "簡體中文" or "Chinese", data = "zh"},
            {description = simplified_chinese and "繁体中文"
                or traditional_chinese and "繁體中文" or "Traditional Chinese", data = "zh_tw"},
            {description = chinese and "English" or "English", data = "en"},
        },
        default = traditional_chinese and "zh_tw" or simplified_chinese and "zh" or "en",
    },
}
