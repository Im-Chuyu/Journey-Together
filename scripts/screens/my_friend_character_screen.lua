local Widget = require "widgets/widget"
local Screen = require "widgets/screen"
local Menu = require "widgets/menu"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local Text = require "widgets/text"
local TEMPLATES = require "widgets/redux/templates"
local Characters = require("my_friend_characters")
local TextForLanguage = require("my_friend_strings").Text

-- CurlyWindow draws itself at scale .7, so every number below that is meant to
-- be read in screen pixels has already been divided through by that.
-- 1000x500 is exactly where CurlyWindow clamps, so this is as much room as the
-- frame can be given.
local PANEL_W, PANEL_H = 1000, 500
local PANEL_SCALE = .7
local VIEW_W, VIEW_H = PANEL_W * PANEL_SCALE, PANEL_H * PANEL_SCALE

-- The band between the hint line and the button row.
local GRID_TOP, GRID_BOTTOM = 112, -96
local GRID_H = GRID_TOP - GRID_BOTTOM
local GRID_W = VIEW_W - 48

-- The avatar art is about 95px square in its atlas, so a cell wider than this
-- would only upscale a blurry icon. ICON_PAD keeps a gap between neighbours
-- that survives the 1.1x scale_on_focus bump on the hovered one.
local MAX_CELL = 110
local ICON_PAD = 16
local MIN_COLUMNS, MAX_COLUMNS = 4, 14

-- "carny_long" is 320x89 at the atlas and Menu draws it at scale .7, so the
-- button is 224 wide. The old 150 spacing overlapped the two buttons by a
-- third of their width; vanilla CurlyWindow uses 230 for the same style.
local BUTTON_SPACING = 250

-- The prefab's own name, not its epithet: STRINGS.NAMES.WILSON is "威尔逊",
-- while GetCharacterTitle would give "绅士科学家". Whatever language pack is
-- installed has already localised STRINGS, so a character translated into
-- Chinese reads Chinese and one that only ships English reads English.
-- Mod characters that register no NAMES entry fall back to the prefab.
local function DisplayName(character)
    local name = (STRINGS.NAMES or {})[string.upper(character)]
    return type(name) == "string" and name ~= "" and name or character
end

-- Pick whichever column count leaves the icons largest. Hard-coding 6 columns
-- forced 14 characters into 3 rows and let the row height, not the icon art,
-- decide the size. The same roster in 7 columns is 2 rows and the cells nearly
-- double. Ties keep the fewer columns, which is the squarer block.
local function ChooseLayout(count)
    local best
    for columns = MIN_COLUMNS, MAX_COLUMNS do
        local rows = math.max(1, math.ceil(count / columns))
        local cell = math.floor(math.min(MAX_CELL, GRID_W / columns, GRID_H / rows))
        if best == nil or cell > best.cell then
            best = { columns = columns, rows = rows, cell = cell }
        end
    end
    return best
end

-- Selectable() drops the paid characters, so everything offered here is free
-- for every player and the server validates it against the same rule.
local function Available(current)
    local list = Characters.Selectable()
    table.sort(list, function(a, b)
        if (a == current) ~= (b == current) then return a == current end
        return a < b
    end)
    return list
end

local FriendCharacterScreen = Class(Screen, function(self, friend, owner)
    Screen._ctor(self, "MyFriendCharacterScreen")
    self.friend = friend
    self.owner = owner
    self.current = friend ~= nil and friend.prefab or nil
    self.selected = self.current

    self.proot = self:AddChild(Widget("ROOT"))
    self.proot:SetHAnchor(ANCHOR_MIDDLE)
    self.proot:SetVAnchor(ANCHOR_MIDDLE)
    self.proot:SetScaleMode(SCALEMODE_PROPORTIONAL)

    self.black = self.proot:AddChild(Image("images/global.xml", "square.tex"))
    self.black:SetSize(4000, 4000)
    self.black:SetTint(0, 0, 0, .75)

    self.panel = self.proot:AddChild(TEMPLATES.CurlyWindow(PANEL_W, PANEL_H,
        TextForLanguage("换个伙伴", "Choose a Companion"), nil, nil, nil))

    self.hint = self.proot:AddChild(Text(DEFAULTFONT, 18))
    self.hint:SetRegionSize(GRID_W, 46)
    self.hint:EnableWordWrap(true)
    self.hint:SetString(TextForLanguage(
        "选一个新伙伴。老伙伴会告别离开，东西留在原地，新伙伴从头开始。",
        "Pick a new companion. The old one leaves its things behind and says goodbye."))
    self.hint:SetPosition(0, 138)
    self.hint:SetColour(1, .85, .45, 1)

    self.buttons = {}
    local list = Available(self.current)
    local layout = ChooseLayout(#list)
    local columns, rows, cell = layout.columns, layout.rows, layout.cell
    -- Fixed padding normally, proportional once the cells get small, so the
    -- 1.1x hover bump can never make two icons touch no matter how many
    -- character mods are installed.
    local icon = math.max(cell * .7, cell - ICON_PAD)
    local centre = (GRID_TOP + GRID_BOTTOM) / 2
    for index, character in ipairs(list) do
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        -- Centre every row on its own contents. A part-filled last row left
        -- aligned against the first column reads as crooked next to the full
        -- rows above it.
        local in_row = math.min(columns, #list - row * columns)
        local atlas, texture = "images/avatars.xml", "avatar_unknown.tex"
        if GetCharacterAvatarTextureLocation ~= nil then
            atlas, texture = GetCharacterAvatarTextureLocation(character)
        end
        local button = self.proot:AddChild(ImageButton(atlas, texture))
        button:ForceImageSize(icon, icon)
        button.scale_on_focus = true
        button:SetPosition((col - (in_row - 1) / 2) * cell,
            centre + ((rows - 1) / 2 - row) * cell)
        button:SetHoverText(DisplayName(character))
        button.character = character
        button:SetOnClick(function() self:Select(character) end)
        self.buttons[#self.buttons + 1] = button
    end

    self.menu = self.proot:AddChild(Menu({
        { text = TextForLanguage("取消", "Cancel"), cb = function() self:Cancel() end },
        { text = TextForLanguage("确定", "Confirm"), cb = function() self:Apply() end },
    }, BUTTON_SPACING, true, "carny_long", nil, 30))
    -- Menu lays items out left to right from its own origin, so the row has to
    -- be pushed back by half its width to sit centred under the grid.
    self.menu:SetPosition(-BUTTON_SPACING / 2, -VIEW_H / 2 + 35)
    self.default_focus = self.menu
    self:Refresh()
    SetAutopaused(true)
end)

function FriendCharacterScreen:Select(character)
    self.selected = character
    self:Refresh()
end

function FriendCharacterScreen:Refresh()
    for _, button in ipairs(self.buttons) do
        local chosen = button.character == self.selected
        button:SetImageNormalColour(chosen and 1 or .55, chosen and 1 or .55,
            chosen and 1 or .55, 1)
    end
end

function FriendCharacterScreen:OnControl(control, down)
    if FriendCharacterScreen._base.OnControl(self, control, down) then return true end
    if control == CONTROL_CANCEL and not down then
        self:Cancel()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
        return true
    end
end

function FriendCharacterScreen:Cancel()
    TheFrontEnd:PopScreen(self)
end

function FriendCharacterScreen:Apply()
    if self.friend ~= nil and self.friend:IsValid()
        and self.selected ~= nil and self.selected ~= self.current then
        SendModRPCToServer(GetModRPC("MyFriends", "SwitchCharacter"),
            self.friend, self.selected)
    end
    TheFrontEnd:PopScreen(self)
end

function FriendCharacterScreen:OnDestroy()
    SetAutopaused(false)
    self._base.OnDestroy(self)
end

return FriendCharacterScreen
