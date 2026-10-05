-- Run from the mod root: lua tests/panel_scroll_test.lua
package.path = "scripts/?.lua;" .. package.path

Class = function(base, ctor)
    local cls = {}
    cls.__index = cls
    cls._ctor = ctor
    return setmetatable(cls, {__index = base, __call = function(_, ...)
        local value = setmetatable({}, cls)
        ctor(value, ...)
        return value
    end})
end

local methods = {
    SetPosition = function(self, x, y) self.x, self.y = x, y end,
    SetScale = function(self, scale) self.scale = scale end,
    CancelScaleTo = function(self) self.scale_cancelled = true end,
    ClearFocus = function(self) self.focus = false end,
    SetTile = function(self, tile) self.tile = tile end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    Kill = function(self) self.killed = true end,
}
local InvSlot = setmetatable({_ctor = function(self, num)
    self.num = num
end}, {__index = methods})

for _, name in ipairs({"widget", "image", "imagebutton", "text", "itemslot",
    "healthbadge", "hungerbadge", "sanitybadge", "moisturemeter"}) do
    package.loaded["widgets/" .. name] = methods
end
package.loaded["widgets/invslot"] = InvSlot
local tiles = 0
package.loaded["widgets/itemtile"] = function(item)
    tiles = tiles + 1
    return {item = item, Refresh = function(self) self.refreshed = true end}
end
package.loaded.my_friend_strings = {Text = function(chinese) return chinese end}

local overflow = {items = {}}
for i = 1, 100 do overflow.items[i] = {slot = i} end
function overflow:GetNumSlots() return 100 end
package.loaded.my_friend_equip_slots = {
    Panel = function() return {} end,
    BackpackContainer = function() return overflow end,
    ContainerItem = function(_, num) return overflow.items[num] end,
}

local config
package.loaded["widgets/redux/templates"] = {ScrollingGrid = function(items, opts)
    config = opts
    local scroll = {items = items, widgets = {}}
    for i = 1, (opts.num_visible_rows + 2) * opts.num_columns do
        scroll.widgets[i] = opts.item_ctor_fn(opts.scroll_context, i)
    end
    function scroll:GetListWidgets() return self.widgets end
    function scroll:SetPosition(x, y) self.x, self.y = x, y end
    function scroll:Kill() self.killed = true end
    function scroll:Render(first)
        for i, widget in ipairs(self.widgets) do
            opts.apply_fn(opts.scroll_context, widget, items[first + i - 1], first + i - 1)
        end
    end
    scroll:Render(1)
    return scroll
end}

local Panel = require("widgets/my_friend_panel")
local panel = setmetatable({owner = {}, friend = {replica = {inventory = {}}},
    slots = {}, equips = {}, backpackslots = {},
    AddChild = function(_, child) return child end}, Panel)
panel:RebuildSlots()
local scroll = panel.backpack_scroll
assert(scroll ~= nil and #scroll.items == 100 and #panel.backpackslots == 25)
assert(config.num_columns == 5 and config.num_visible_rows == 3)
assert(scroll.x == 420 and scroll.y == -2)

local function check(first)
    scroll:Render(first)
    for i, widget in ipairs(panel.backpackslots) do
        local num = first + i - 1
        assert(widget.num == num and widget.shown and widget.tile.item.slot == num)
    end
end
check(1)
check(36)
check(76)
local before = tiles
check(76)
assert(tiles == before, "unchanged rows must retain their item tiles")
scroll:Render(96)
for i = 1, 5 do assert(panel.backpackslots[i].num == 95 + i) end
for i = 6, 25 do assert(not panel.backpackslots[i].shown) end
check(1)
assert(panel.backpackslots[1].scale == 1)
panel:ClearSlots()
assert(scroll.killed and #panel.backpackslots == 0)
print("PASS: 100-slot scrolling grid reuses 25 slots without gaps or tile churn")
