local Widget = require "widgets/widget"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local Text = require "widgets/text"
local Language = require "my_friend_strings"
local LanguageFiles = require "my_friend_language"
local Characters = require "my_friend_characters"

local WheelButton = Class(ImageButton, function(self, wheel, slot, size)
    ImageButton._ctor(self, "images/button_icons.xml", "circle.tex")
    self.wheel = wheel
    self.slot = slot
    self:ForceImageSize(size or 112, size or 112)
    self:SetImageNormalColour(.08, .1, .13, .96)
    self:SetImageFocusColour(.25, .22, .1, 1)
    self:SetImageDisabledColour(.05, .06, .08, .85)
    self.scale_on_focus = false
    self:SetClickable(true)
end)

-- ImageButton handles the left click through OnControl.  Right click is
-- delivered through the widget mouse path, so intercept it here first.
function WheelButton:OnMouseButton(button, down, x, y)
    if down and button == (MOUSEBUTTON_RIGHT or 1001) then
        self.wheel:OpenCommandPicker(self.slot)
        return true
    end
    return false
end

local LABELS = {
    follow = {"跟随", "跟隨", "Follow"},
    stop_follow = {"停止跟随", "停止跟隨", "Stop Following"},
    hold_position = {"原地待命", "原地待命", "Hold Position"},
    set_base = {"设置基地", "設定基地", "Set Base"},
    backpack = {"捡包", "撿包", "Pick Up Backpack"},
    hoe = {"锄地", "鋤地", "Hoe"},
    water = {"浇水", "澆水", "Water"},
    harvest = {"收农作物", "收農作物", "Harvest Crops"},
}

local DEFAULT_COMMANDS = {
    "follow", "stop_follow", "hold_position", "set_base",
    "backpack", "hoe", "water", "harvest",
}
local PICKER_PAGE_SIZE = 32

local function CurrentText(entry)
    if Language.language == "en" then return entry[3] end
    if Language.language == "zh_tw" then return entry[2] end
    return entry[1]
end

local function CommandLabel(id, keywords, label)
    if type(label) == "string" and label ~= "" then return label end
    local known = LABELS[id]
    if known ~= nil then return CurrentText(known) end
    return keywords ~= nil and keywords[1] or id
end

local function CommandList()
    local result, seen = {}, {}
    local function Add(configured)
        for _, entry in ipairs(configured or {}) do
            if type(entry) == "table" and type(entry.id) == "string"
                and type(entry.keywords) == "table" and #entry.keywords > 0
                and not seen[entry.id] then
                seen[entry.id] = true
                result[#result + 1] = {id = entry.id,
                    label = CommandLabel(entry.id, entry.keywords, entry.label)}
            end
        end
    end
    Add(LanguageFiles.CommandWords(Language.language))
    -- Character commands live beside each character's language/dialogue file,
    -- but the picker intentionally exposes the complete catalogue at once.
    for _, character in ipairs(Characters.List()) do
        Add(LanguageFiles.CharacterCommandWords(Language.language, character))
    end
    return result
end

local MyFriendCommandWheel = Class(Widget, function(self, owner)
    Widget._ctor(self, "MyFriendCommandWheel")
    self.owner = owner
    self.friend = nil
    self.slot = nil
    self.commands = {}
    for i, id in ipairs(DEFAULT_COMMANDS) do self.commands[i] = id end
    self.command_list = CommandList()
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetScale(.86)

    self.center = self:AddChild(Image("images/button_icons.xml", "circle.tex"))
    self.center:SetSize(132, 132)
    self.center:SetTint(.18, .15, .08, .98)
    self.center:SetClickable(false)
    self.center_label = self:AddChild(Text(DEFAULTFONT, 22, Language.Text("伙伴指令", "Companion")))
    self.center_label:SetColour(1, .84, .38, 1)
    self.center_label:SetClickable(false)

    self.buttons = {}
    local radius = 154
    for i = 1, 8 do
        local angle = math.pi / 2 - (i - 1) * math.pi / 4
        local button = self:AddChild(WheelButton(self, i, 112))
        button:SetPosition(math.cos(angle) * radius, math.sin(angle) * radius)
        button.label = button:AddChild(Text(DEFAULTFONT, 17, ""))
        button.label:SetColour(1, .86, .46, 1)
        button.label:SetClickable(false)
        button:SetOnClick(function() self:Choose(i) end)
        self.buttons[i] = button
    end

    self.picker = self:AddChild(Widget("MyFriendCommandPicker"))
    self.picker_bg = self.picker:AddChild(Image("images/global.xml", "square.tex"))
    self.picker_bg:SetSize(980, 690)
    self.picker_bg:SetTint(.012, .018, .028, .97)
    self.picker_bg:SetClickable(false)
    self.picker_title = self.picker:AddChild(Text(DEFAULTFONT, 28,
        Language.Text("选择要替换的指令", "Choose a command")))
    self.picker_title:SetPosition(0, 315)
    self.picker_title:SetColour(1, .84, .38, 1)
    self.picker_title:SetClickable(false)
    self.picker_close = self.picker:AddChild(ImageButton("images/button_icons.xml", "circle.tex"))
    self.picker_close:ForceImageSize(54, 54)
    self.picker_close:SetPosition(440, 315)
    self.picker_close:SetImageNormalColour(.16, .08, .06, 1)
    self.picker_close:SetImageFocusColour(.35, .15, .08, 1)
    self.picker_close.scale_on_focus = false
    self.picker_close.icon = self.picker_close:AddChild(Text(DEFAULTFONT, 25, "X"))
    self.picker_close.icon:SetColour(1, .82, .42, 1)
    self.picker_close.icon:SetClickable(false)
    self.picker_close:SetOnClick(function() self:CloseCommandPicker() end)
    self.picker_items = {}
    self.picker_page = 1
    local function PickerNav(label, x, delta)
        local button = self.picker:AddChild(ImageButton("images/global.xml", "square.tex"))
        button:ForceImageSize(126, 36)
        button:SetPosition(x, -315)
        button:SetImageNormalColour(.08, .1, .13, .98)
        button:SetImageFocusColour(.25, .22, .1, 1)
        button.scale_on_focus = false
        button.label = button:AddChild(Text(DEFAULTFONT, 16, label))
        button.label:SetColour(1, .86, .46, 1)
        button.label:SetClickable(false)
        button:SetOnClick(function() self:ChangePickerPage(delta) end)
        return button
    end
    self.picker_prev = PickerNav(Language.Text("上一页", "Previous"), -180, -1)
    self.picker_next = PickerNav(Language.Text("下一页", "Next"), 180, 1)
    self.picker_page_label = self.picker:AddChild(Text(DEFAULTFONT, 18, ""))
    self.picker_page_label:SetPosition(0, -315)
    self.picker_page_label:SetColour(1, .84, .38, 1)
    self.picker_page_label:SetClickable(false)
    self.picker:Hide()
    self:RefreshLabels()
end)

function MyFriendCommandWheel:RefreshLabels()
    for i, button in ipairs(self.buttons) do
        local id = self.commands[i]
        local label = id
        for _, entry in ipairs(self.command_list) do
            if entry.id == id then label = entry.label break end
        end
        button.label:SetTruncatedString(label, 94, 42, true)
    end
end

function MyFriendCommandWheel:Choose(slot)
    local id = self.commands[slot]
    if self.friend ~= nil and self.friend:IsValid() and id ~= nil then
        SendModRPCToServer(GetModRPC("MyFriends", "WheelCommand"), self.friend, id)
    end
    self:HideWheel()
end

function MyFriendCommandWheel:RenderPickerPage()
    for _, item in ipairs(self.picker_items) do item:Kill() end
    self.picker_items = {}
    local columns, step_x, step_y = 4, 230, 58
    local page_count = math.max(1, math.ceil(#self.command_list / PICKER_PAGE_SIZE))
    self.picker_page = math.max(1, math.min(self.picker_page, page_count))
    local first = (self.picker_page - 1) * PICKER_PAGE_SIZE + 1
    local last = math.min(#self.command_list, first + PICKER_PAGE_SIZE - 1)
    local rows = math.ceil(math.max(0, last - first + 1) / columns)
    local top = math.min(270, (rows - 1) * step_y / 2)
    for index = first, last do
        local entry = self.command_list[index]
        local page_index = index - first + 1
        local col = (page_index - 1) % columns
        local row = math.floor((page_index - 1) / columns)
        local button = self.picker:AddChild(ImageButton("images/global.xml", "square.tex"))
        button:ForceImageSize(208, 44)
        button:SetPosition((col - 1.5) * step_x, top - row * step_y)
        button:SetImageNormalColour(.08, .1, .13, .98)
        button:SetImageFocusColour(.25, .22, .1, 1)
        button.scale_on_focus = false
        button.label = button:AddChild(Text(DEFAULTFONT, 17, entry.label))
        button.label:SetColour(1, .86, .46, 1)
        button.label:SetClickable(false)
        button:SetOnClick(function()
            self.commands[self.slot] = entry.id
            self:RefreshLabels()
            self:CloseCommandPicker()
        end)
        self.picker_items[#self.picker_items + 1] = button
    end
    self.picker_prev:SetFadeAlpha(self.picker_page > 1 and 1 or .35)
    self.picker_next:SetFadeAlpha(self.picker_page < page_count and 1 or .35)
    self.picker_page_label:SetString(string.format("%d / %d", self.picker_page, page_count))
end

function MyFriendCommandWheel:ChangePickerPage(delta)
    local page_count = math.max(1, math.ceil(#self.command_list / PICKER_PAGE_SIZE))
    local page = math.max(1, math.min(self.picker_page + delta, page_count))
    if page ~= self.picker_page then
        self.picker_page = page
        self:RenderPickerPage()
    end
end

function MyFriendCommandWheel:OpenCommandPicker(slot)
    if self.commands[slot] == nil then return end
    self.slot = slot
    self.picker_page = 1
    self:RenderPickerPage()
    self.picker:Show()
end

function MyFriendCommandWheel:CloseCommandPicker()
    self.slot = nil
    self.picker:Hide()
end

function MyFriendCommandWheel:FindFriend()
    local controls = self.owner ~= nil and self.owner.HUD ~= nil and self.owner.HUD.controls or nil
    local panel = controls ~= nil and controls.my_friend_panel or nil
    if panel ~= nil and panel.friend ~= nil and panel.friend:IsValid()
        and panel.friend:HasTag("my_friend") then return panel.friend end
    local target = TheInput ~= nil and TheInput:GetWorldEntityUnderMouse() or nil
    if target ~= nil and target:IsValid() and target:HasTag("my_friend") then return target end
    if self.owner == nil or not self.owner:IsValid() then return nil end
    local px, py, pz = self.owner.Transform:GetWorldPosition()
    -- Selecting a target is a client convenience only.  The server still
    -- decides whether the selected command is valid for the companion.
    -- Search all currently replicated companions so the wheel can open and
    -- target one even when it is farther away than the normal command range.
    local entities = {}
    for _, entity in pairs(Ents or {}) do
        if entity ~= nil and entity:IsValid() and entity:HasTag("my_friend") then
            entities[#entities + 1] = entity
        end
    end
    local best, best_dist
    for _, entity in ipairs(entities) do
        if entity:IsValid() then
            local ex, ey, ez = entity.Transform:GetWorldPosition()
            local dist = (ex - px) ^ 2 + (ez - pz) ^ 2
            if best_dist == nil or dist < best_dist then best, best_dist = entity, dist end
        end
    end
    return best
end

function MyFriendCommandWheel:ShowFor(friend)
    if friend ~= nil and (not friend:IsValid() or not friend:HasTag("my_friend")) then return false end
    self.friend = friend
    self:CloseCommandPicker()
    self:Show()
    self:MoveToFront()
    return true
end

function MyFriendCommandWheel:HideWheel()
    self:CloseCommandPicker()
    self.friend = nil
    self:Hide()
end

function MyFriendCommandWheel:Toggle()
    if self:IsVisible() then
        self:HideWheel()
        return
    end
    self:ShowFor(self:FindFriend())
end

return MyFriendCommandWheel
