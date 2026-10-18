local Widget = require("widgets/widget")
local Text = require("widgets/text")
local TextEdit = require("widgets/textedit")
local TEMPLATES = require("widgets/redux/templates")
local UI = require("widgets/my_friend_games_ui")
local Protocol = require("my_friend_games_chat")
local L = require("my_friend_games_strings")
local Chat = Class(Widget, function(self, client)
    Widget._ctor(self, "MyFriendGamesChat")
    self.client = client
    UI.Box(self, 0, 0, 880, 148, .075, .1, .12)
    self.history = self:AddChild(TEMPLATES.ScrollingGrid({}, {
        scroll_context = {}, peek_height = 0, widget_width = 820, widget_height = 20,
        num_visible_rows = 5, num_columns = 1, end_offset = 1, scroll_per_click = 1,
        scrollbar_offset = 8, scrollbar_height_offset = -20,
        item_ctor_fn = function()
            local row = Widget("game_chat_row")
            row.sender = UI.Text(row, "", -335, 0, 14, 140)
            row.body = row:AddChild(Text(CHATFONT or DEFAULTFONT, 14, ""))
            row.body:SetPosition(65, 0); row.body:SetRegionSize(620, 18)
            row.body:SetHAlign(ANCHOR_LEFT)
            return row
        end,
        apply_fn = function(_, row, entry)
            if entry == nil then row:Hide(); return end
            row:Show(); row.sender:SetTruncatedString(entry.name, 140, nil, true)
            local text = Protocol.Display(entry)
            -- Native truncation requires autosizing. A fixed Text region
            -- makes width checks ineffective (or can loop forever).
            row.body:ResetRegionSize()
            local fits = row.body:SetTruncatedString(text, 620, nil, true)
            row.body:SetRegionSize(620, 18)
            if not fits then
                row.body:SetHoverText(text, {font = CHATFONT or DEFAULTFONT, font_size = 18,
                    region_w = 620, region_h = 120, wordwrap = true})
            else row.body:ClearHoverText() end
        end,
    }))
    self.history:SetPosition(0, 18)
    self.rows = self.history:GetListWidgets()
    UI.Button(self, L.Get("quick"), -391, -51, 68, 30, function() self:TogglePicker("quick") end)
    UI.Button(self, L.Get("emoji"), -315, -51, 68, 30, function() self:TogglePicker("emoji") end)
    UI.Box(self, 22, -51, 582, 32, .025, .035, .045)
    self.input = self:AddChild(TextEdit(DEFAULTFONT, 20, ""))
    self.input:SetPosition(22, -51); self.input:SetRegionSize(560, 30); self.input:SetHAlign(ANCHOR_LEFT)
    self.input:SetTextLengthLimit(80); self.input:SetAllowNewline(false)
    self.input:SetIdleTextColour(.95, .95, .95, 1); self.input:SetEditTextColour(1, 1, 1, 1)
    self.input:SetEditCursorColour(1, .8, .4, 1)
    self.input:SetTextPrompt(L.Get("chat_prompt"), {.6, .65, .7, 1})
    self.input.OnTextEntered = function(value)
        local text = type(value) == "string" and value or self.input:GetLineEditString()
        if client.Chat("text", text) then self.input:SetString("") end
    end
    UI.Button(self, L.Get("send"), 375, -51, 100, 30, function()
        self.input.OnTextEntered(self.input:GetLineEditString())
    end)
end)
function Chat:Refresh()
    local match = self.client.match
    local entries = match ~= nil and match.chat or {}
    local seq = match ~= nil and match.chat_seq or 0
    local game = match ~= nil and match.id or nil
    if self.game == game and self.seq == seq then return end
    local list = self.history
    local position = list.current_scroll_pos or 1
    local bottom = (list.target_scroll_pos or position) >= (list.end_pos or 1) - .01
    local anchor = list.items ~= nil and list.items[math.floor(position)] or nil
    local anchor_seq = anchor ~= nil and anchor.seq or nil
    list:SetItemsData(entries)
    if self.game ~= game or self.seq == nil or bottom then list:ScrollToDataIndex(#entries)
    else
        local target = 1
        for i, entry in ipairs(entries) do if entry.seq == anchor_seq then target = i; break end end
        list:ScrollToScrollPos(math.max(1, math.min(list.end_pos, target + position % 1)))
    end
    self.game, self.seq = game, seq
end
function Chat:TogglePicker(kind)
    if self.picker ~= nil then
        self.picker:Kill(); self.picker, self.emoji_grid = nil, nil
        if self.picker_kind == kind then self.picker_kind = nil; return end
    end
    self.picker_kind = kind
    local popup = self:AddChild(Widget("game_chat_picker")); self.picker = popup
    popup:SetPosition(-235, 80)
    UI.Box(popup, 0, 0, 390, 220, .1, .14, .17)
    local function Send(value)
        if self.client.Chat(kind, value) then
            popup:Kill(); self.picker, self.picker_kind, self.emoji_grid = nil, nil, nil
        end
    end
    if kind == "quick" then
        for i = 1, Protocol.QUICK_COUNT do
            local value = i
            UI.Button(popup, L.Get("quick_" .. i), 0, 80 - (i - 1) * 38, 370, 32, function() Send(value) end)
        end
    else
        self.emoji_grid = popup:AddChild(TEMPLATES.ScrollingGrid(Protocol.EmojiCatalog(true), {
            scroll_context = {}, peek_height = 0, widget_width = 70, widget_height = 44,
            num_visible_rows = 4, num_columns = 5, end_offset = 1, scroll_per_click = 1,
            scrollbar_offset = 0, scrollbar_height_offset = -12,
            item_ctor_fn = function()
                local button
                button = UI.Button(nil, "", 0, 0, 62, 38, function() if button.emoji ~= nil then Send(button.emoji) end end)
                button.label:SetFont(CHATFONT or DEFAULTFONT)
                return button
            end,
            apply_fn = function(_, button, name)
                button.emoji = name
                if name == nil then button:Hide(); return end
                button:Show(); button.label:SetString(Protocol.Glyph(name)); button:SetHoverText(":" .. name .. ":")
            end,
        }))
    end
end
return Chat
