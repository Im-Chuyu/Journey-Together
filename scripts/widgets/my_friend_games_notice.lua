local Widget = require("widgets/widget")
local UI = require("widgets/my_friend_games_ui")
local L = require("my_friend_games_strings")
local Notice = Class(Widget, function(self, client)
    Widget._ctor(self, "MyFriendGamesNotice")
    self:SetHAnchor(ANCHOR_MIDDLE); self:SetVAnchor(ANCHOR_TOP)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL); self:SetPosition(0, -118)
    self.button = UI.Button(self, "", 0, 0, 270, 38, function()
        if client.invite ~= nil then client.Show("invitation")
        elseif client.match ~= nil then client.Send("resume", {}) end
    end)
end)
function Notice:Refresh(client)
    if client.invite ~= nil then self.button.label:SetString(L.Get("incoming")); self:Show()
    elseif client.match ~= nil and client.screen == nil then self.button.label:SetString(L.Get("resume")); self:Show()
    else self:Hide() end
end
return Notice
