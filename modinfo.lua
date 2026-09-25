local simplified_chinese = locale == "zh" or locale == "zhr"
local traditional_chinese = locale == "zht" or locale == "zh_tw" or locale == "zh-tw"
local chinese = simplified_chinese or traditional_chinese
name = chinese and "一路同行" or "Journey Together"
description = simplified_chinese and "在这片永恒大陆，我会与你并肩同行。"
    or traditional_chinese and "在這片永恆大陸，我會與你並肩同行。"
    or "On this eternal continent, I will travel with you."
author = "阮秀"
version = "1.7.3"
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
    {
        name = "voice_enabled",
        label = simplified_chinese and "伙伴语音"
            or traditional_chinese and "夥伴語音"
            or "Companion Voice",
        options = {
            {description = simplified_chinese and "开启"
                or traditional_chinese and "開啟" or "Enabled", data = true},
            {description = simplified_chinese and "关闭"
                or traditional_chinese and "關閉" or "Disabled", data = false},
        },
        default = true,
    },
    {
        name = "command_wheel_key",
        label = simplified_chinese and "指令轮盘 Alt 快捷键"
            or traditional_chinese and "指令輪盤 Alt 快捷鍵"
            or "Command Wheel Shortcut",
        options = {
            {description = "Alt+A", data = "a"}, {description = "Alt+B", data = "b"},
            {description = "Alt+C", data = "c"}, {description = "Alt+D", data = "d"},
            {description = "Alt+E", data = "e"}, {description = "Alt+F", data = "f"},
            {description = "Alt+G", data = "g"}, {description = "Alt+H", data = "h"},
            {description = "Alt+I", data = "i"}, {description = "Alt+J", data = "j"},
            {description = "Alt+K", data = "k"}, {description = "Alt+L", data = "l"},
            {description = "Alt+M", data = "m"}, {description = "Alt+N", data = "n"},
            {description = "Alt+O", data = "o"}, {description = "Alt+P", data = "p"},
            {description = "Alt+Q", data = "q"}, {description = "Alt+R", data = "r"},
            {description = "Alt+S", data = "s"}, {description = "Alt+T", data = "t"},
            {description = "Alt+U", data = "u"}, {description = "Alt+V", data = "v"},
            {description = "Alt+W", data = "w"}, {description = "Alt+X", data = "x"},
            {description = "Alt+Y", data = "y"}, {description = "Alt+Z", data = "z"},
        },
        default = "r",
    },
}
