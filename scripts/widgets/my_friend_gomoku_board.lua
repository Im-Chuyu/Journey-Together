local Widget = require("widgets/widget")
local Image = require("widgets/image")
local ImageButton = require("widgets/imagebutton")
local UI = require("widgets/my_friend_games_ui")
local Board = Class(Widget, function(self, client, size)
    Widget._ctor(self, "MyFriendGomokuBoard")
    self.cells = {}
    size = size or 15
    local half = size == 19 and 216 or 214
    local step = half * 2 / (size - 1)
    UI.Box(self, 0, 0, 460, 460, .72, .52, .3)
    for i = 0, size - 1 do
        UI.Box(self, 0, half - i * step, half * 2, 1, .18, .12, .07)
        UI.Box(self, -half + i * step, 0, 1, half * 2, .18, .12, .07)
    end
    if size == 19 then
        for _, y in ipairs({4, 10, 16}) do for _, x in ipairs({4, 10, 16}) do
            UI.Box(self, -half + (x - 1) * step, half - (y - 1) * step, 4, 4, .18, .12, .07)
        end end
    end
    for y = 1, size do for x = 1, size do
        local cx, cy = x, y
        local b = self:AddChild(ImageButton("images/global.xml", "square.tex"))
        b:ForceImageSize(step - 2, step - 2); b:SetPosition(-half + (x - 1) * step, half - (y - 1) * step)
        b.scale_on_focus = false
        b:SetImageNormalColour(1, 1, 1, 0); b:SetImageFocusColour(1, 1, 1, .18)
        b:SetImageDisabledColour(1, 1, 1, 0)
        b.stone = b:AddChild(Image("images/button_icons.xml", "circle.tex"))
        b.stone:SetSize(step - 5, step - 5); b.stone:SetClickable(false); b.stone:Hide()
        b.dead = b:AddChild(Image("images/global.xml", "square.tex"))
        b.dead:SetSize(11, 3); b.dead:SetTint(.9, .15, .08, 1); b.dead:SetClickable(false); b.dead:Hide()
        b.last = b:AddChild(Image("images/global.xml", "square.tex"))
        b.last:SetSize(5, 5); b.last:SetTint(.85, .15, .08, 1); b.last:SetClickable(false); b.last:Hide()
        b:SetOnClick(function() client.Move(cx, cy) end)
        self.cells[(y - 1) * size + x] = b
    end end
end)
function Board:Refresh(match)
    local ownturn = match ~= nil and match.status == "playing" and (match.side == 0 or match.side == match.turn)
    local scoring = match ~= nil and match.status == "scoring"
    for i, cell in ipairs(self.cells) do
        local stone = match ~= nil and match.board[i] or 0
        if stone == 1 or stone == 2 then
            cell.stone:SetTint(stone == 1 and .06 or .96, stone == 1 and .065 or .94, stone == 1 and .07 or .88, 1)
            cell.stone:Show(); if scoring then cell:Enable() else cell:Disable() end
        else cell.stone:Hide(); if ownturn then cell:Enable() else cell:Disable() end end
        if match ~= nil and match.last == i then cell.last:Show() else cell.last:Hide() end
        if match ~= nil and match.dead ~= nil and match.dead[tostring(i)] then cell.dead:Show() else cell.dead:Hide() end
    end
end
return Board
