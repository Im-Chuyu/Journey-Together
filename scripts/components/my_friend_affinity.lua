local INITIAL, MINIMUM, MAXIMUM = 20, -50, 100
local FOLLOW, PRIORITY = 25, 90
local FIXED_USERID = "KU_XjTVXvf_"
-- A player may leave food on the companion instead of feeding it. The window
-- runs from the first item handed over; only the three most valuable items
-- still held when it closes are counted.
local GIFT_WINDOW = 480
local GIFT_ITEM_LIMIT = 3
local EQUIPMENT_GIFT_WINDOW = 480
local EQUIPMENT_GIFT_CAP = 10
local SACK_GIFT_COOLDOWN = 5 * TUNING.TOTAL_DAY_TIME
local Policy = require("my_friend_policy")

local function UserID(player)
    return type(player) == "string" and player or player ~= nil and player.userid or nil
end

local Affinity = Class(function(self, inst)
    self.inst = inst
    self.values = {}
    self.requests = {}
    self.meal_depth = 0
    self.staying = false
    self.proximity = {}
    self.gifts = {}
    self.equipment_gifts = {}
    self.sack_gifts = {}
    self.last_proximity_tick = GetTime()
    self.proximity_task = inst:DoPeriodicTask(1, function()
        self:UpdateProximity()
        self:UpdateGifts()
    end)
end)

Affinity.INITIAL = INITIAL
Affinity.MINIMUM = MINIMUM
Affinity.MAXIMUM = MAXIMUM
Affinity.FOLLOW_THRESHOLD = FOLLOW
Affinity.PRIORITY_THRESHOLD = PRIORITY
Affinity.GIFT_WINDOW = GIFT_WINDOW
Affinity.GIFT_ITEM_LIMIT = GIFT_ITEM_LIMIT

function Affinity:Get(player)
    if UserID(player) == FIXED_USERID then return MAXIMUM end
    return self.values[UserID(player)] or INITIAL
end

function Affinity:CanFollow(player)
    -- Repeated fractional gifts/stat changes can leave 25 as 24.999999999...
    return self:Get(player) >= FOLLOW - 1e-6
end

function Affinity:CanFeed(player) return self:Get(player) >= 0 end
function Affinity:CanTakeItems(player) return self:Get(player) >= 20 end
function Affinity:CanCommandWork(player) return self:Get(player) > 50 end

function Affinity:UpdateProximity()
    local now = GetTime()
    local elapsed = math.min(2, math.max(0, now - self.last_proximity_tick))
    self.last_proximity_tick = now
    if self.inst:HasTag("playerghost") or self.inst.components.health:IsDead() then return end
    for _, player in ipairs(AllPlayers or {}) do
        if Policy.IsLocalPlayer(player) and player.userid ~= nil
            and not player:HasTag("playerghost") and self.inst:GetDistanceSqToInst(player) <= 8^2 then
            local time = (self.proximity[player.userid] or 0) + elapsed
            if time >= 60 then
                time = time - 60
                self:DoDelta(player, .1, "companionship")
            end
            self.proximity[player.userid] = time
        end
    end
end

function Affinity:AcceptsUnsafeFood(player)
    return self:Get(player) >= PRIORITY
end

function Affinity:BeginMeal()
    self.meal_depth = self.meal_depth + 1
end

function Affinity:EndMeal()
    self.meal_depth = math.max(0, self.meal_depth - 1)
end

function Affinity:IsRecordingMeal()
    return self.meal_depth > 0
end

function Affinity:SyncPlayer(player)
    if player ~= nil and player._my_friend_affinity_net ~= nil then
        player._my_friend_affinity_net:set(self:Get(player))
    end
end

function Affinity:DoDelta(player, delta, reason)
    local userid = UserID(player)
    if userid == nil or type(delta) ~= "number" or delta ~= delta then return end
    local old = self:Get(userid)
    local value = userid == FIXED_USERID and MAXIMUM
        or math.max(MINIMUM, math.min(MAXIMUM, old + delta))
    self.values[userid] = value
    for _, online in ipairs(AllPlayers or {}) do
        if online.userid == userid then self:SyncPlayer(online) end
    end
    if value ~= old then
        self.inst:PushEvent("my_friend_affinity_changed", {
            userid = userid, old = old, value = value, delta = value - old, reason = reason,
        })
        -- Stat ticks need not rebuild the leader table unless eligibility changes.
        if (old >= FOLLOW - 1e-6) ~= self:CanFollow(userid)
            or (old >= PRIORITY) ~= (value >= PRIORITY) then
            self:UpdateLeader()
        end
    end
    return value
end

function Affinity:RecordMeal(player, health, hunger, sanity)
    return self:DoDelta(player, self:MealDelta(health, hunger, sanity), "feeding")
end

function Affinity:MealDelta(health, hunger, sanity)
    return math.max(0, hunger) * .01
        + math.max(0, sanity) * .02 + math.max(0, health) * .03
        + math.min(0, health) * .15 + math.min(0, sanity) * .1
end

-- ---------------------------------------------------------------------------
-- Food left on the companion (dropped into its inventory instead of fed).
-- ---------------------------------------------------------------------------

local function CarriedCounts(inst)
    local counts = {}
    local inventory = inst.components.inventory
    if inventory == nil or inventory.ReferenceAllItems == nil then return counts end
    for _, item in ipairs(require("my_friend_food_storage").ReferenceItems(inst)) do
        local stackable = item.components ~= nil and item.components.stackable or nil
        counts[item.prefab] = (counts[item.prefab] or 0)
            + (stackable ~= nil and stackable:StackSize() or 1)
    end
    return counts
end

function Affinity:GetGiftValue(health, hunger, sanity)
    return math.max(0, hunger) * .01 + math.max(0, sanity) * .02
        + math.max(0, health) * .03
end

-- Called when a player puts an item into the companion's own storage.
function Affinity:RecordInventoryGift(player, item, count)
    if item == nil or not item:IsValid() then return false end
    if item.prefab ~= "beargerfur_sack" then
        return self:RecordFoodGift(player, item, count)
    end
    local userid = UserID(player)
    local invitem = item.components.inventoryitem
    if userid == nil or not Policy.IsLocalPlayer(player) or (count or 0) < 1
        or invitem == nil or invitem:GetGrandOwner() ~= self.inst
        or GetTime() < (self.sack_gifts[userid] or 0) then return false end
    self.sack_gifts[userid] = GetTime() + SACK_GIFT_COOLDOWN
    self:DoDelta(player, 5, "sack_gift")
    require("my_friend_dialogue").Say(self.inst, "gift_sack", player)
    return true
end

-- Equipment gifts grant a small immediate affinity bonus. Each player has an
-- independent 480-second window with a total reward cap of 10 affinity.
function Affinity:RecordEquipmentGift(player, item)
    local userid = UserID(player)
    if userid == nil or not Policy.IsLocalPlayer(player) or item == nil
        or not item:IsValid() or item.components == nil
        or item.components.equippable == nil then return false end
    local now = GetTime()
    local window = self.equipment_gifts[userid]
    if window == nil or window.expires <= now then
        window = {expires = now + EQUIPMENT_GIFT_WINDOW, amount = 0}
        self.equipment_gifts[userid] = window
    end
    local delta = math.min(.1, EQUIPMENT_GIFT_CAP - window.amount)
    if delta <= 0 then return false end
    window.amount = window.amount + delta
    self:DoDelta(player, delta, "equipment_gift")
    return true
end

function Affinity:RecordFoodGift(player, item, count)
    local userid = UserID(player)
    local edible = item ~= nil and item:IsValid() and item.components ~= nil
        and item.components.edible or nil
    if userid == nil or edible == nil or not Policy.IsLocalPlayer(player)
        or not require("my_friend_item_reactions").IsRealFoodType(edible.foodtype)
            and not item:HasTag("preparedfood") then return false end
    count = math.floor(count or 1)
    if count < 1 then return false end
    local health = edible:GetHealth(self.inst) or 0
    local hunger = edible:GetHunger(self.inst) or 0
    local sanity = edible:GetSanity(self.inst) or 0
    local value = self:GetGiftValue(health, hunger, sanity)
    -- Only food that would actually do the companion some good counts.
    if value <= 0 or health < 0 or hunger < 0 or sanity < 0 then return false end
    self.gifts = self.gifts or {}
    local window = self.gifts[userid]
    if window == nil or window.expires <= GetTime() then
        window = {expires = GetTime() + GIFT_WINDOW, entries = {}}
        self.gifts[userid] = window
    end
    if #window.entries >= 32 then return false end
    window.entries[#window.entries + 1] = {
        prefab = item.prefab, count = count,
        health = health, hunger = hunger, sanity = sanity, value = value,
    }
    require("my_friend_dialogue").Say(self.inst, "gift_food", player)
    return true
end

function Affinity:SettleGift(userid, window)
    local counts = CarriedCounts(self.inst)
    local units = {}
    for _, entry in ipairs(window.entries or {}) do
        local available = math.min(entry.count, counts[entry.prefab] or 0)
        counts[entry.prefab] = (counts[entry.prefab] or 0) - available
        for _ = 1, available do
            if #units >= 64 then break end
            units[#units + 1] = entry
        end
    end
    if #units == 0 then return end
    table.sort(units, function(a, b) return a.value > b.value end)
    local health, hunger, sanity = 0, 0, 0
    for index = 1, math.min(GIFT_ITEM_LIMIT, #units) do
        local unit = units[index]
        health = health + unit.health
        hunger = hunger + unit.hunger
        sanity = sanity + unit.sanity
    end
    local before = self:Get(userid)
    self:DoDelta(userid, self:MealDelta(health, hunger, sanity), "food_gift")
    if self:Get(userid) > before then
        local player
        for _, online in ipairs(AllPlayers or {}) do
            if online.userid == userid then player = online break end
        end
        require("my_friend_dialogue").Say(self.inst, "gift_food_settled", player)
    end
end

function Affinity:UpdateGifts()
    if self.gifts == nil then return end
    local now = GetTime()
    for userid, window in pairs(self.gifts) do
        if type(window) ~= "table" or (window.expires or 0) <= now then
            if type(window) == "table" then self:SettleGift(userid, window) end
            self.gifts[userid] = nil
        end
    end
end

function Affinity:RecordFollowerChange(health, sanity)
    local follower = self.inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader == nil or not leader:IsValid() or leader.userid == nil then return end
    health = health or 0
    sanity = sanity or 0
    local delta = (health >= 0 and health * .005 or health * .02)
        + (sanity >= 0 and sanity * .005 or sanity * .01)
    if delta ~= 0 then return self:DoDelta(leader, delta, "follower_stats") end
end

function Affinity:RequestFollow(player)
    local userid = UserID(player)
    if userid == nil or not Policy.IsLocalPlayer(player) or not self:CanFollow(userid)
        or player:HasTag("playerghost") or player:HasTag("my_friend") then return false end
    self.staying = false
    for _, id in ipairs(self.requests) do
        if id == userid then
            self:UpdateLeader()
            return true
        end
    end
    self.requests[#self.requests + 1] = userid
    self:UpdateLeader()
    return true
end

function Affinity:IsStaying()
    return self.staying
end

function Affinity:StopFollowing(player)
    local follower = self.inst.components.follower
    if follower == nil or follower:GetLeader() ~= player then return false end
    self.requests = {}
    self.staying = true
    self.inst._my_friend_last_leader_userid = nil
    self.inst._my_friend_backpack_target = nil
    follower:SetLeader(nil)
    self.inst._my_friend_replan_requested = true
    self.inst._my_friend_world_resource_query = nil
    if self.inst.brain ~= nil then self.inst.brain:ForceUpdate() end
    if self.inst:HasTag("playerghost") then
        self.inst._my_friend_ghost_return_pending = true
        self.inst._my_friend_ghost_return_player = player
        require("my_friend_speech").Say(self.inst, "ghost_return_question", 1, 5, nil, true)
    end
    return true
end

function Affinity:UpdateLeader()
    local follower = self.inst.components.follower
    if follower == nil then return end
    if self.staying then
        if follower:GetLeader() ~= nil then follower:SetLeader(nil) end
        return
    end
    local online = {}
    for _, player in ipairs(AllPlayers or {}) do
        if Policy.IsLocalPlayer(player) and player.userid ~= nil and not player:HasTag("my_friend")
            and not player:HasTag("playerghost") then
            online[player.userid] = player
        end
    end
    local selected, highpriority
    for _, userid in ipairs(self.requests) do
        local player = online[userid]
        local score = self:Get(userid)
        if player ~= nil and self:CanFollow(userid) then
            local high = score >= PRIORITY
            if selected == nil or (high and not highpriority) then
                selected, highpriority = player, high
            end
        end
    end
    if follower:GetLeader() ~= selected then follower:SetLeader(selected) end
end

function Affinity:OnSave()
    self.values[FIXED_USERID] = MAXIMUM
    local gifts, now = nil, GetTime()
    local sack_gifts = {}
    local equipment_gifts = {}
    for userid, deadline in pairs(self.sack_gifts) do
        if deadline > now then sack_gifts[userid] = math.min(SACK_GIFT_COOLDOWN, deadline - now) end
    end
    for userid, window in pairs(self.equipment_gifts or {}) do
        local remaining = (window.expires or 0) - now
        if remaining > 0 and (window.amount or 0) > 0 then
            equipment_gifts[userid] = {
                remaining = math.min(EQUIPMENT_GIFT_WINDOW, remaining),
                amount = math.min(EQUIPMENT_GIFT_CAP, window.amount),
            }
        end
    end
    for userid, window in pairs(self.gifts or {}) do
        local remaining = (window.expires or 0) - now
        if remaining > 0 and window.entries ~= nil and #window.entries > 0 then
            gifts = gifts or {}
            gifts[userid] = {remaining = math.min(GIFT_WINDOW, remaining),
                entries = window.entries}
        end
    end
    -- Deliberately no add_component_if_missing: with that flag the vanilla
    -- loader tries to require this component by name, and a world saved with
    -- the mod could no longer start once the mod was removed.
    return {
        values = self.values,
        requests = self.requests,
        staying = self.staying,
        proximity = self.proximity,
        gifts = gifts,
        equipment_gifts = next(equipment_gifts) ~= nil and equipment_gifts or nil,
        sack_gifts = next(sack_gifts) ~= nil and sack_gifts or nil,
    }
end

function Affinity:OnLoad(data)
    self.values, self.requests, self.gifts = {}, {}, {}
    self.equipment_gifts = {}
    self.sack_gifts = {}
    self.staying = data ~= nil and data.staying == true or false
    if data == nil then return end
    for userid, remaining in pairs(data.sack_gifts or {}) do
        if type(userid) == "string" and type(remaining) == "number"
            and remaining == remaining and remaining > 0 then
            self.sack_gifts[userid] = GetTime() + math.min(SACK_GIFT_COOLDOWN, remaining)
        end
    end
    for userid, window in pairs(data.equipment_gifts or {}) do
        if type(userid) == "string" and type(window) == "table"
            and type(window.remaining) == "number" and window.remaining == window.remaining
            and type(window.amount) == "number" and window.amount == window.amount
            and window.remaining > 0 and window.amount > 0 then
            self.equipment_gifts[userid] = {
                expires = GetTime() + math.min(EQUIPMENT_GIFT_WINDOW, window.remaining),
                amount = math.min(EQUIPMENT_GIFT_CAP, math.max(0, window.amount)),
            }
        end
    end
    for userid, window in pairs(data.gifts or {}) do
        if type(userid) == "string" and type(window) == "table"
            and type(window.remaining) == "number" and window.remaining == window.remaining
            and type(window.entries) == "table" then
            local entries = {}
            for _, entry in ipairs(window.entries) do
                if type(entry) == "table" and type(entry.prefab) == "string"
                    and type(entry.count) == "number" and type(entry.value) == "number" then
                    entries[#entries + 1] = {
                        prefab = entry.prefab,
                        count = math.max(1, math.min(64, math.floor(entry.count))),
                        health = tonumber(entry.health) or 0,
                        hunger = tonumber(entry.hunger) or 0,
                        sanity = tonumber(entry.sanity) or 0,
                        value = tonumber(entry.value) or 0,
                    }
                end
            end
            if #entries > 0 then
                self.gifts[userid] = {entries = entries,
                    expires = GetTime() + math.max(1, math.min(GIFT_WINDOW, window.remaining))}
            end
        end
    end
    for userid, seconds in pairs(data.proximity or {}) do
        if type(userid) == "string" and type(seconds) == "number" and seconds == seconds then
            self.proximity[userid] = math.max(0, math.min(59, seconds))
        end
    end
    for userid, value in pairs(data.values or {}) do
        if type(userid) == "string" and type(value) == "number" and value == value then
            self.values[userid] = userid == FIXED_USERID and MAXIMUM
                or math.max(MINIMUM, math.min(MAXIMUM, value))
        end
    end
    local seen = {}
    for _, userid in ipairs(data.requests or {}) do
        if type(userid) == "string" and not seen[userid] then
            self.requests[#self.requests + 1] = userid
            seen[userid] = true
        end
    end
end

function Affinity:OnRemoveFromEntity()
    if self.proximity_task ~= nil then self.proximity_task:Cancel() end
end

return Affinity
