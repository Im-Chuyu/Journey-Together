local simplified_chinese = locale == "zh" or locale == "zhr"
local traditional_chinese = locale == "zht" or locale == "zh_tw" or locale == "zh-tw"
local russian = locale == "ru" or locale == "ru_ru" or locale == "ru-ru"
local chinese = simplified_chinese or traditional_chinese
name = simplified_chinese and "一路同行"
    or traditional_chinese and "一路同行"
    or russian and "Путь вместе"
    or "Journey Together"
description = simplified_chinese and "在这片永恒大陆，我会与你并肩同行。"
    or traditional_chinese and "在這片永恆大陸，我會與你並肩同行。"
    or russian and "На этом вечном континенте я буду путешествовать вместе с тобой."
    or "On this eternal continent, I will travel with you."
author = "阮秀"
version = "3.0.2"
forumthread = ""
api_version = 10

dst_compatible = true
all_clients_require_mod = true
client_only_mod = false
server_filter_tags = {"companion", "伙伴"}

icon_atlas = "friend.xml"
icon = "friend.tex"

local function ExtraKeyOptions()
    local result = {{description = simplified_chinese and "关闭" or traditional_chinese and "關閉"
        or russian and "Отключено" or "Disabled", data = "DISABLED"}}
    for i = 1, 12 do result[#result + 1] = {description = "F" .. i, data = "F" .. i} end
    return result
end

local function UIButtonOptions()
    return {
        {description = simplified_chinese and "关闭" or traditional_chinese and "關閉"
            or russian and "Отключено" or "Disabled", data = false},
        {description = simplified_chinese and "开启" or traditional_chinese and "開啟"
            or russian and "Включено" or "Enabled", data = true},
    }
end

configuration_options = {
    {
        name = "model_enabled",
        label = simplified_chinese and "AI大模型模式" or traditional_chinese and "AI大模型模式"
            or russian and "Режим ИИ" or "AI Model Mode",
        hover = simplified_chinese and "启用模型接口及自动连接，无需先跟随。公屏带伙伴名字即可聊天；跟随时只接受领队安排工作。重试间隔递增5秒，连续30次失败停止。"
            or traditional_chinese and "啟用模型介面及自動連線，無需先跟隨。公頻帶夥伴名字即可聊天；跟隨時只接受領隊安排工作。重試間隔遞增5秒，連續30次失敗停止。"
            or russian and "Автоподключение без следования. В чате называйте спутника по имени; при следовании работу задаёт только лидер. Интервал +5 секунд, до 30 ошибок."
            or "Connects automatically without following. Address the companion by name in chat; while following, only the leader can assign work. Retry delay +5 seconds, up to 30 failures.",
        options = UIButtonOptions(), default = false,
    },
    {
        name = "command_wheel_extra_key",
        label = simplified_chinese and "指令轮盘额外快捷键" or traditional_chinese and "指令輪盤額外快捷鍵"
            or russian and "Доп. клавиша колеса команд" or "Additional Command Wheel Key",
        hover = simplified_chinese and "保留原来的 Alt+字母快捷键。" or traditional_chinese and "保留原來的 Alt+字母快捷鍵。"
            or russian and "Сочетание Alt+буква продолжает работать." or "The existing Alt+letter shortcut still works.",
        options = ExtraKeyOptions(), default = "DISABLED",
    },
    {
        name = "companion_panel_extra_key",
        label = simplified_chinese and "伙伴面板额外快捷键" or traditional_chinese and "夥伴面板額外快捷鍵"
            or russian and "Доп. клавиша панели спутника" or "Additional Companion Panel Key",
        hover = simplified_chinese and "保留 Alt+鼠标右键；优先打开鼠标下伙伴的面板。" or traditional_chinese and "保留 Alt+滑鼠右鍵；優先開啟滑鼠下夥伴的面板。"
            or russian and "Alt+ПКМ также работает. Приоритет у спутника под курсором." or "Alt+right-click still works. Prefers the companion under the cursor.",
        options = ExtraKeyOptions(), default = "DISABLED",
    },
    {
        name = "companion_panel_ui_button",
        label = simplified_chinese and "伙伴背包面板按钮" or traditional_chinese and "夥伴背包面板按鈕"
            or russian and "Кнопка инвентаря спутника" or "Companion Inventory Button",
        hover = simplified_chinese and "在屏幕顶部居中显示可点击或触摸的伙伴面板按钮。"
            or traditional_chinese and "在螢幕頂部置中顯示可點擊或觸摸的夥伴面板按鈕。"
            or russian and "Показывает вверху по центру экрана кнопку панели спутника для мыши и касаний."
            or "Show a companion panel button at the top center for mouse or touch input.",
        options = UIButtonOptions(), default = false,
    },
    {
        name = "command_wheel_ui_button",
        label = simplified_chinese and "指令轮盘按钮" or traditional_chinese and "指令輪盤按鈕"
            or russian and "Кнопка колеса команд" or "Command Wheel Button",
        hover = simplified_chinese and "在屏幕顶部居中显示可点击或触摸的指令轮盘按钮。"
            or traditional_chinese and "在螢幕頂部置中顯示可點擊或觸摸的指令輪盤按鈕。"
            or russian and "Показывает вверху по центру экрана кнопку колеса команд для мыши и касаний."
            or "Show a command wheel button at the top center for mouse or touch input.",
        options = UIButtonOptions(), default = false,
    },
    {
        name = "language",
        label = simplified_chinese and "伙伴语言"
            or traditional_chinese and "夥伴語言"
            or russian and "Язык спутника"
            or "Companion Language",
        options = {
            -- Add a new {description = "...", data = "xx"} entry after the
            -- reviewed files are added under scripts/languages/xx/.
            {description = simplified_chinese and "中文"
                or traditional_chinese and "簡體中文"
                or russian and "Китайский"
                or "Chinese", data = "zh"},
            {description = simplified_chinese and "繁体中文"
                or traditional_chinese and "繁體中文"
                or russian and "Традиционный китайский"
                or "Traditional Chinese", data = "zh_tw"},
            {description = chinese and "English"
                or russian and "Английский"
                or "English", data = "en"},
            {description = simplified_chinese and "俄语"
                or traditional_chinese and "俄語"
                or russian and "Русский"
                or "Russian", data = "ru"},
        },
        default = traditional_chinese and "zh_tw"
            or simplified_chinese and "zh"
            or russian and "ru"
            or "en",
    },
    {
        name = "voice_enabled",
        label = simplified_chinese and "伙伴语音"
            or traditional_chinese and "夥伴語音"
            or russian and "Голос спутника"
            or "Companion Voice",
        options = {
            {description = simplified_chinese and "开启"
                or traditional_chinese and "開啟"
                or russian and "Включён"
                or "Enabled", data = true},
            {description = simplified_chinese and "关闭"
                or traditional_chinese and "關閉"
                or russian and "Выключен"
                or "Disabled", data = false},
        },
        default = true,
    },
    {
        name = "command_wheel_key",
        label = simplified_chinese and "指令轮盘 Alt 快捷键"
            or traditional_chinese and "指令輪盤 Alt 快捷鍵"
            or russian and "Клавиша колеса команд с Alt"
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
-- Standard DST mod configuration has no free-form text field; six digit
-- selectors allow an arbitrary code without adding a custom configuration UI.
for i = 1, 6 do
    local digits = {}
    for digit = 0, 9 do digits[#digits + 1] = {description = "" .. digit, data = "" .. digit} end
    configuration_options[#configuration_options + 1] = {
        name = "model_pair_digit_" .. i,
        label = simplified_chinese and ("模型配对码第" .. i .. "位") or traditional_chinese and ("模型配對碼第" .. i .. "位")
            or russian and ("Цифра кода ИИ " .. i) or ("Model Pairing Code Digit " .. i),
        hover = simplified_chinese and "六位组合须与助手设置一致，默认321151。" or traditional_chinese and "六位組合須與助手設定一致，預設321151。"
            or russian and "Совпадает с кодом помощника; по умолчанию 321151." or "Must match the assistant code; default 321151.",
        options = digits, default = ("321151"):sub(i, i),
    }
end
