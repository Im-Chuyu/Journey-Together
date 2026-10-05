local Widget = require "widgets/widget"
local Screen = require "widgets/screen"
local Menu = require "widgets/menu"
local Image = require "widgets/image"
local Text = require "widgets/text"
local ImageButton = require "widgets/imagebutton"
local TextForLanguage = require("my_friend_strings").Text

local FriendSkinScreen = Class(Screen, function(self, friend, owner)
    Screen._ctor(self, "MyFriendSkinScreen")
    self.friend = friend
    self.owner = owner
    self.proot = self:AddChild(Widget("ROOT"))
    self.proot:SetHAnchor(ANCHOR_MIDDLE)
    self.proot:SetVAnchor(ANCHOR_MIDDLE)
    self.proot:SetScaleMode(SCALEMODE_PROPORTIONAL)

    self.background = self.proot:AddChild(Image(
        "images/bg_redux_wardrobe_bg.xml", "wardrobe_bg.tex"))
    self.background:SetScale(.8)
    self.background:SetPosition(-200, 0)
    self.background:SetTint(1, 1, 1, .96)

    -- The wardrobe always follows whichever character the companion is now.
    local character = friend ~= nil and friend.prefab
        or require("my_friend_characters").DEFAULT
    local initial = { base = character .. "_none", body = "", hand = "", legs = "", feet = "" }
    local raw = friend._my_friend_skin_net ~= nil and friend._my_friend_skin_net:value() or ""
    local base, body, hand, legs, feet = raw:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if base ~= nil and base ~= "" then initial.base = base end
    initial.body, initial.hand = body or "", hand or ""
    initial.legs, initial.feet = legs or "", feet or ""

    local ok, loadout = false, nil
    if Profile ~= nil and type(Profile.GetSkinsForCharacter) == "function"
        and type(Profile.SetSkinsForCharacter) == "function" then
        ok, loadout = pcall(function()
            local LoadoutSelect = require "widgets/redux/loadoutselect"
            return LoadoutSelect(Profile, character, nil, true, nil, true, initial)
        end)
    end
    if ok and loadout ~= nil then
        self.loadout = self.proot:AddChild(loadout)
    else
        -- Mobile clients can ship LoadoutSelect without its required profile API.
        self.loadout = self.proot:AddChild(Widget("MobileLoadout"))
        self.loadout.selected_skins = {
            base = initial.base, body = initial.body, hand = initial.hand,
            legs = initial.legs, feet = initial.feet,
        }
        local owned, sets = require("my_friend_skins").Scan(character)
        local function Choices(current, default, available)
            local result, seen = {}, {}
            for _, skin in ipairs({current, default}) do
                if not seen[skin] then result[#result + 1], seen[skin] = skin, true end
            end
            for _, skin in ipairs(available) do
                if not seen[skin] then result[#result + 1], seen[skin] = skin, true end
            end
            return result
        end
        local choices = {base = Choices(initial.base, character .. "_none", owned)}
        for _, part in ipairs({"body", "hand", "legs", "feet"}) do
            choices[part] = Choices(initial[part], "", sets[part] or {})
        end
        local y = 150
        local function AddChoice(part, zh, en)
            local button = self.loadout:AddChild(ImageButton("images/global.xml", "square.tex"))
            button:ForceImageSize(330, 42)
            button:SetPosition(0, y)
            button:SetImageNormalColour(.12, .12, .14, .95)
            button:SetImageFocusColour(.32, .26, .12, 1)
            button.scale_on_focus = false
            button.label = button:AddChild(Text(DEFAULTFONT, 18, ""))
            button.label:SetColour(1, .78, .28, 1)
            local index = 1
            local function Refresh()
                local value = choices[part][index]
                self.loadout.selected_skins[part] = value
                button.label:SetString(TextForLanguage(zh, en) .. ": "
                    .. (value == "" and TextForLanguage("默认", "Default") or value))
            end
            button:SetOnClick(function()
                index = index % #choices[part] + 1
                Refresh()
            end)
            Refresh()
            self.fallback_focus = self.fallback_focus or button
            y = y - 52
        end
        AddChoice("base", "基础", "Base")
        AddChoice("body", "身体", "Body")
        AddChoice("hand", "手部", "Hand")
        AddChoice("legs", "腿部", "Legs")
        AddChoice("feet", "足部", "Feet")
    end
    self.character = character
    self.loadout:SetPosition(-306, 0)
    if type(self.loadout.SetDefaultMenuOption) == "function" then
        self.loadout:SetDefaultMenuOption()
    end

    self.menu = self.proot:AddChild(Menu({
        { text = STRINGS.UI.WARDROBE_POPUP.CANCEL, cb = function() self:Cancel() end },
        { text = STRINGS.UI.WARDROBE_POPUP.SET, cb = function() self:Apply() end },
    }, 70, false, "carny_long", nil, 30))
    self.menu:SetPosition(493, -260, 0)
    self.default_focus = self.fallback_focus or self.loadout
    self.menu:SetFocusChangeDir(MOVE_LEFT, self.default_focus)
    self.default_focus:SetFocusChangeDir(MOVE_RIGHT, self.menu)
    SetAutopaused(true)
end)

function FriendSkinScreen:OnControl(control, down)
    if FriendSkinScreen._base.OnControl(self, control, down) then
        return true
    end

    if control == CONTROL_CANCEL and not down then
        self:Cancel()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
        return true
    elseif control == CONTROL_MENU_START and not down then
        self:Apply()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
        return true
    end
end

function FriendSkinScreen:Cancel()
    TheFrontEnd:PopScreen(self)
end

function FriendSkinScreen:Apply()
    local skins = self.loadout.selected_skins
    if self.friend ~= nil and self.friend:IsValid() and self.friend.prefab == self.character then
        -- Refresh immediately before applying: another report may have replaced
        -- the server's list while this screen was open.
        require("my_friend_skins").Report(self.character)
        SendModRPCToServer(GetModRPC("MyFriends", "SetSkins"),
            self.friend, skins.base or (self.character .. "_none"),
            skins.body or "", skins.hand or "", skins.legs or "", skins.feet or "")
    end
    TheFrontEnd:PopScreen(self)
end

function FriendSkinScreen:OnUpdate(dt)
    if type(self.loadout.OnUpdate) == "function" then self.loadout:OnUpdate(dt) end
end

function FriendSkinScreen:OnDestroy()
    SetAutopaused(false)
    self._base.OnDestroy(self)
end

return FriendSkinScreen
