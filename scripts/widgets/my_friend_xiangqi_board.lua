local Widget = require("widgets/widget")
local Image = require("widgets/image")
local ImageButton = require("widgets/imagebutton")
local UI = require("widgets/my_friend_games_ui")
local L = require("my_friend_games_strings")
local Rules = require("my_friend_xiangqi")
local Board = Class(Widget, function(self, client)
    Widget._ctor(self, "MyFriendXiangqiBoard")
    self.client, self.cells = client, {}
    UI.Box(self, 0, 0, 430, 460, .76, .57, .34)
    for y = 1, 10 do UI.Box(self, 0, 207 - (y - 1) * 46, 368, 1, .2, .13, .07) end
    for x = 1, 9 do
        local px = -184 + (x - 1) * 46
        if x == 1 or x == 9 then UI.Box(self, px, 0, 1, 414, .2, .13, .07)
        else
            UI.Box(self, px, 115, 1, 184, .2, .13, .07)
            UI.Box(self, px, -115, 1, 184, .2, .13, .07)
        end
    end
    for _, py in ipairs({161, -161}) do
        UI.Box(self, 0, py, 130, 1, .2, .13, .07):SetRotation(45)
        UI.Box(self, 0, py, 130, 1, .2, .13, .07):SetRotation(-45)
    end
    UI.Text(self, L.Get("xiangqi_river_left"), -96, 0, 23)
    UI.Text(self, L.Get("xiangqi_river_right"), 96, 0, 23)
    for i = 1, 90 do
        local x, y = (i - 1) % 9 + 1, math.floor((i - 1) / 9) + 1
        local b = self:AddChild(ImageButton("images/global.xml", "square.tex"))
        b:ForceImageSize(44, 44); b.scale_on_focus = false; b.move_on_click = false
        b:SetImageNormalColour(1, 1, 1, 0); b:SetImageFocusColour(1, 1, 1, .18)
        b:SetImageDisabledColour(1, 1, 1, 0)
        b.mark = b:AddChild(Image("images/button_icons.xml", "circle.tex"))
        b.mark:SetSize(44, 44); b.mark:SetTint(.95, .72, .08, .9); b.mark:SetClickable(false)
        b.piece = b:AddChild(Image("images/button_icons.xml", "circle.tex"))
        b.piece:SetSize(38, 38); b.piece:SetTint(.96, .85, .59, 1); b.piece:SetClickable(false)
        -- DEFAULTFONT's outlined CJK fallback thickens dark strokes. Share an
        -- unoutlined face and compensate its glyph baseline on both armies.
        b.label = UI.Text(b, "", 0, 4, 27, 36)
        b.label:SetFont(CHATFONT)
        b.hint = UI.Box(b, 0, 0, 7, 7, .15, .6, .2, .9)
        b:SetOnClick(function() client.Move(x, y) end)
        self.cells[i] = b
    end
    self:Refresh(nil)
end)
function Board:Refresh(match)
    local active = match ~= nil and match.status == "playing" and self.client.pending_move == nil
        and (match.side == 0 or match.side == match.turn)
    local from = active and self.client.selected_from or nil
    local flipped = match ~= nil and match.side == 2
    local board = match ~= nil and match.board or nil
    for i, cell in ipairs(self.cells) do
        local display = flipped and 91 - i or i
        cell:SetPosition(-184 + ((display - 1) % 9) * 46, 207 - math.floor((display - 1) / 9) * 46)
        local piece = board ~= nil and board[i] or 0
        if piece ~= 0 then
            local side = Rules.Side(piece)
            cell.piece:Show(); cell.label:Show()
            cell.label:SetString(L.Get("xiangqi_" .. (side == 1 and "red_" or "black_") .. Rules.Kind(piece)))
            cell.label:SetColour(side == 1 and .75 or .1, .08, .06, 1)
        else cell.piece:Hide(); cell.label:Hide() end
        if from == i or match ~= nil and (match.last == i or match.last_from == i) then cell.mark:Show() else cell.mark:Hide() end
        if from ~= nil and Rules.Legal(board, match.turn, from, i) then cell.hint:Show() else cell.hint:Hide() end
        if active then cell:Enable() else cell:Disable() end
    end
end
return Board
