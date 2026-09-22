local chinese = locale == "zh" or locale == "zhr" or locale == "zht"
name = chinese and "一路同行" or "Journey Together"
description = chinese and "在这片永恒大陆，我会与你并肩同行。"
    or "On this eternal continent, I will travel with you."
author = "阮秀"
version = "1.6.6"
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
        label = chinese and "伙伴语言" or "Companion Language",
        options = {
            -- Add a new {description = "...", data = "xx"} entry after the
            -- reviewed files are added under scripts/languages/xx/.
            {description = chinese and "中文" or "Chinese", data = "zh"},
            {description = "English", data = "en"},
        },
        default = chinese and "zh" or "en",
    },
}
