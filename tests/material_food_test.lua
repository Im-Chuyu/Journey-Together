-- Real gift/affinity/reaction/feed code and native burnt-material definitions.
-- Run from the mod root: lua tests/material_food_test.lua [native scripts path]
local native = arg[1] or "../yuanma/scripts"
package.path = "./scripts/?.lua;" .. native .. "/?.lua;" .. package.path
require("class")
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a"); file:close()
    return (value:gsub("\r\n", "\n"))
end
local types = assert(Read(native .. "/constants.lua"):match("FOODTYPE%s*=%s*(%b{})"))
FOODTYPE = assert(loadstring("return " .. types))()
FOODGROUP = {OMNI = {name = "omni", types = {FOODTYPE.GENERIC, FOODTYPE.VEGGIE, FOODTYPE.MEAT}}}
ACTIONS = {FEEDPLAYER = {}, OTHER = {}}
TUNING = {TOTAL_DAY_TIME = 480}
local now, lines = 0, {}
function GetTime() return now end
package.loaded.my_friend_dialogue = {Say = function(_, kind) lines[#lines + 1] = kind end}
package.loaded.my_friend_inventory = {MarkPlayerAdded = function(item) item.player_added = true end}
local Food = require("my_friend_food_ai")
local Feeding = require("my_friend_feeding")
local Reactions = require("my_friend_item_reactions")
local Gifts = require("my_friend_gifts")
local Affinity = require("components/my_friend_affinity")

local function Entity(prefab)
    local inst = {prefab = prefab, components = {}, replica = {}, tags = {}, items = {}}
    function inst:IsValid() return true end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function inst:DoPeriodicTask() return {Cancel = function() end} end
    function inst:PushEvent() end
    return inst
end
local function Setup()
    now, lines = 0, {}
    local friend, player = Entity("wendy"), Entity("wilson")
    friend.tags.my_friend = true
    player.userid = "KU_material_food"
    AllPlayers = {player}
    friend.components.inventory = {ReferenceAllItems = function()
        local copy = {}; for i, item in ipairs(friend.items) do copy[i] = item end; return copy
    end}
    friend.components.my_friend_affinity = Affinity(friend)
    return friend, player, friend.components.my_friend_affinity
end
local function Item(prefab, owner, foodtype)
    local item = Entity(prefab)
    item.owner = owner
    item.components.inventoryitem = {GetGrandOwner = function() return item.owner end}
    item.components.stackable = {StackSize = function() return 1 end}
    local edible = {foodtype = foodtype, healthvalue = 1, hungervalue = 12.5, sanityvalue = 0}
    function edible:GetHealth() return self.healthvalue end
    function edible:GetHunger() return self.hungervalue end
    function edible:GetSanity() return self.sanityvalue end
    item.components.edible = edible
    if prefab == "charcoal" or prefab == "ash" then
        -- Read the native assignments so tests retain BURNT and its tempting +20 values.
        local source = Read(native .. "/prefabs/" .. prefab .. ".lua")
        local found = 0
        for assignment in source:gmatch("inst%.components%.edible%.[^\n]+") do
            if assignment:match("^inst%.components%.edible%.%w+%s*=") then
                local chunk = assert(loadstring(assignment))
                setfenv(chunk, setmetatable({inst = item}, {__index = _G}))
                chunk(); found = found + 1
            end
        end
        assert(found == 3 and edible.foodtype == FOODTYPE.BURNT)
    end
    item.tags["edible_" .. edible.foodtype] = true
    return item
end
local function LegacyEntry(prefab)
    return {prefab = prefab, count = 1, health = 20, hunger = 20, sanity = 0, value = .8}
end
local passed = 0
local function Test(name, fn)
    fn(); passed = passed + 1; print("PASS " .. name)
end

Test("native charcoal and ash remain owned materials without food-gift dialogue or affinity", function()
    local friend, player, affinity = Setup()
    for _, prefab in ipairs({"charcoal", "ash"}) do
        local item = Item(prefab, friend)
        friend.items[#friend.items + 1] = item
        assert(not Gifts.Record(friend, player, item, 1))
        assert(item.owner == friend and item.player_added)
        assert(Reactions.Kind(item) == nil and Food.IsNonFoodMaterial(item))
        assert(Food.IsForbiddenFood(item) and not Food.IsUsableFood(friend, item))
    end
    now = 241; affinity:UpdateGifts()
    assert(#lines == 0 and next(affinity.gifts) == nil and affinity:Get(player) == 20)
end)

Test("native trade wrapper still accepts and protects material gifts without food reactions", function()
    local friend, player, affinity = Setup()
    friend.components.trader = {inst = friend, AcceptGift = function(_, _, item)
        item.owner = friend; friend.items[#friend.items + 1] = item; return true
    end}
    Gifts.Configure(friend)
    for _, prefab in ipairs({"charcoal", "ash"}) do
        local item = Item(prefab, player)
        assert(friend.components.trader:AcceptGift(player, item, 1))
        assert(item.owner == friend and item.player_added)
    end
    assert(#lines == 0 and next(affinity.gifts) == nil)
end)

Test("actual feed handler refuses materials before consulting character diet", function()
    local friend, player = Setup()
    friend.sg = {HasStateTag = function(_, tag) return tag == "idle" end,
        HasAnyStateTag = function() return false end}
    friend.components.eater = {CanEat = function() error("material reached eater") end}
    for _, prefab in ipairs({"charcoal", "ash"}) do
        assert(not Feeding.Feed({target = friend, doer = player, invobject = Item(prefab, player)}))
    end
    local consulted = false
    friend.components.eater.CanEat = function() consulted = true; return false end
    assert(not Feeding.Feed({target = friend, doer = player,
        invobject = Item("carrot", player, FOODTYPE.VEGGIE)}))
    assert(consulted)
end)

Test("client action filtering works without server edible components", function()
    local source = Read("modmain.lua")
    local callback = assert(source:match('AddComponentAction%("USEITEM", "edible", (.-)\nend%)'))
    local chunk = assert(loadstring("return " .. callback .. "\nend"))
    setfenv(chunk, setmetatable({Feeding = Feeding}, {__index = _G}))
    local filter = chunk()
    local friend, player = Setup()
    player._my_friend_affinity_net = {value = function() return 100 end}
    for _, prefab in ipairs({"charcoal", "ash"}) do
        local item = Item(prefab, player)
        item.components = {}
        local actions = {ACTIONS.FEEDPLAYER, ACTIONS.OTHER}
        filter(item, player, friend, actions, true)
        assert(#actions == 1 and actions[1] == ACTIONS.OTHER)
    end
    local actions = {ACTIONS.FEEDPLAYER}
    filter(Item("carrot", player, FOODTYPE.VEGGIE), player, friend, actions, true)
    assert(actions[1] == ACTIONS.FEEDPLAYER)
end)

Test("normal food gifts and take reactions retain their original reward and dialogue", function()
    local friend, player, affinity = Setup()
    local carrot = Item("carrot", friend, FOODTYPE.VEGGIE)
    friend.items = {carrot}
    assert(Gifts.Record(friend, player, carrot, 1) and lines[1] == "gift_food")
    assert(Reactions.Kind(carrot) == "player_takes_food")
    now = 241; affinity:UpdateGifts()
    assert(affinity:Get(player) > 20 and lines[2] == "gift_food_settled")
    assert(Reactions.Kind(Item("beargerfur_sack", friend, FOODTYPE.WOOD)) == "player_takes_sack")
end)

Test("old saved material gifts are discarded while valid food entries survive reload", function()
    local friend, player, affinity = Setup()
    affinity:OnLoad({gifts = {[player.userid] = {remaining = 10,
        entries = {LegacyEntry("charcoal"), LegacyEntry("ash"), LegacyEntry("carrot")}}}})
    assert(#affinity.gifts[player.userid].entries == 1)
    assert(affinity.gifts[player.userid].entries[1].prefab == "carrot")
    local saved = affinity:OnSave()
    assert(#saved.gifts[player.userid].entries == 1)
    affinity:OnLoad({gifts = {[player.userid] = {remaining = 10,
        entries = {LegacyEntry("charcoal"), LegacyEntry("ash")}}}})
    assert(next(affinity.gifts) == nil and #lines == 0)
end)

Test("unsettled legacy material entries cannot award food affinity or thanks", function()
    local friend, player, affinity = Setup()
    friend.items = {Item("charcoal", friend), Item("ash", friend)}
    affinity.gifts[player.userid] = {expires = 1, entries = {LegacyEntry("charcoal"), LegacyEntry("ash")}}
    now = 2; affinity:UpdateGifts()
    assert(affinity:Get(player) == 20 and #lines == 0 and next(affinity.gifts) == nil)
end)

print(string.format("%d material food tests passed", passed))
