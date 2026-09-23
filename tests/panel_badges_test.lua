-- Run from the mod root: lua tests/panel_badges_test.lua
-- Optional argument: path to Uncompromising Mode's postinit/widgets/healthbadge.lua
package.path = "scripts/?.lua;" .. package.path
Class = function(base, ctor)
    return setmetatable({_ctor = ctor}, {__index = base})
end
for _, name in ipairs({"widget", "image", "imagebutton", "invslot", "itemtile", "text",
    "itemslot", "healthbadge", "hungerbadge", "sanitybadge", "moisturemeter", "uianim"}) do
    package.loaded["widgets/" .. name] = {}
end
local Panel = require("widgets/my_friend_panel")
local colours = {}
local healthbadge = {
    -- Skip unrelated ice shield widget construction when loading UM's hook.
    iceshield = {},
    topperanim = {GetAnimState = function()
        return {SetMultColour = function(_, r) colours[#colours + 1] = r end}
    end},
    SetPercent = function(self, val, max, penalty)
        self.args = {val, max, penalty}
        assert(type(max) == "number", "health maximum must be supplied")
    end,
}
if arg[1] ~= nil then
    GLOBAL = _G
    TUNING = {DSTU = {UI_HEALTHPENALTY_GREY = true}}
    env = {AddClassPostConstruct = function(name, hook)
        assert(name == "widgets/healthbadge")
        hook(healthbadge, {})
    end}
    assert(loadfile(arg[1]))()
else
    -- Same comparison that crashed at UM healthbadge.lua:137.
    local original = healthbadge.SetPercent
    function healthbadge:SetPercent(val, max, penalty)
        original(self, val, max, penalty)
        self.topperanim:GetAnimState():SetMultColour(penalty < .25 and .2 or 0)
    end
end
local function badge()
    return {SetPercent = function(self, ...) self.args = {...} end}
end
local panel = {friend = {}, statusbadges = {healthbadge, badge(), badge()}}
-- Construction occurs before the first network payload arrives.
Panel.RefreshStatusBadges(panel)
assert(healthbadge.args[1] == 0 and healthbadge.args[2] == 100 and healthbadge.args[3] == 0)
assert(colours[#colours] == .2)

panel.friend.replica = {
    health = {GetPenaltyPercent = function() return .3 end},
    sanity = {GetPenaltyPercent = function() return .1 end},
}
Panel.RefreshStatusBadges(panel, 105, 150, 80, 200, 100, 150)
assert(healthbadge.args[1] == .7 and healthbadge.args[2] == 150 and healthbadge.args[3] == .3)
assert(colours[#colours] == 0)
assert(panel.statusbadges[2].args[1] == .4 and panel.statusbadges[2].args[2] == 200)
assert(panel.statusbadges[3].args[1] == 100 / 150 and panel.statusbadges[3].args[2] == 150)
assert(panel.statusbadges[3].args[3] == .1)

Panel.RefreshStatusBadges(panel, 0, 0, 0, 0, 0, 0)
for _, b in ipairs(panel.statusbadges) do assert(b.args[1] == 0) end
panel.statusbadges = nil
Panel.RefreshStatusBadges(panel)
print("PASS: panel initialization, status maxima, penalties, zero values, and UM health badge")
