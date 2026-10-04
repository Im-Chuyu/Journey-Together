local Widget = require "widgets/widget"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local Language = require "my_friend_strings"

local function Text(zh, zh_tw, en, ru)
    return Language.language == "zh_tw" and zh_tw or Language.Text(zh, en, ru)
end

local HUDButtons = Class(Widget, function(self, show_panel, show_wheel, toggle_panel, toggle_wheel)
    Widget._ctor(self, "MyFriendHUDButtons")
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetVAnchor(ANCHOR_TOP)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(1.25)
    self:SetPosition(0, -40)

    local total = (show_panel and 1 or 0) + (show_wheel and 1 or 0)
    local count = 0
    local function Button(hover, callback)
        local button = self:AddChild(ImageButton("images/button_icons.xml", "circle.tex"))
        button:ForceImageSize(64, 64)
        button:SetScale(1.1)
        button:SetImageNormalColour(.12, .12, .14, .95)
        button:SetImageFocusColour(.3, .25, .12, 1)
        -- Offset only the background; the icon stays at the button centre.
        button.image_offset = {0, -5}
        button.image:SetPosition(0, -5)
        button.scale_on_focus = false
        button.move_on_click = false
        button:SetPosition(count * 80 - (total - 1) * 40, 0)
        button:SetHoverText(hover)
        button:SetOnClick(callback)
        count = count + 1
        return button
    end

    if show_panel then
        self.panel = Button(Text("伙伴背包", "夥伴背包", "Companion Inventory", "Инвентарь спутника"),
            toggle_panel)
        self.panel.icon = self.panel:AddChild(Image("images/inventoryimages.xml", "backpack.tex"))
        self.panel.icon:ScaleToSize(46, 46)
        self.panel.icon:SetClickable(false)
    end
    if show_wheel then
        self.wheel = Button(Text("指令轮盘", "指令輪盤", "Command Wheel", "Колесо команд"),
            toggle_wheel)
        -- Mirror the eight command slots without introducing a custom atlas.
        for i = 1, 8 do
            local angle = math.pi / 2 - (i - 1) * math.pi / 4
            local dot = self.wheel:AddChild(Image("images/button_icons.xml", "circle.tex"))
            dot:ScaleToSize(8, 8)
            dot:SetPosition(math.cos(angle) * 19, math.sin(angle) * 19)
            dot:SetTint(1, .84, .38, 1)
            dot:SetClickable(false)
        end
        self.wheel.icon = self.wheel:AddChild(Image("images/button_icons.xml", "circle.tex"))
        self.wheel.icon:ScaleToSize(12, 12)
        self.wheel.icon:SetTint(1, .84, .38, 1)
        self.wheel.icon:SetClickable(false)
    end
end)

return HUDButtons
