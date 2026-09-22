local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")
local Dialogue = require("my_friend_dialogue")

local M = {}

local function Uses(book)
    return book.components.finiteuses ~= nil and book.components.finiteuses:GetUses() or math.huge
end

local function Carried(inst, book)
    return book:IsValid() and book.components.inventoryitem ~= nil
        and book.components.inventoryitem:GetGrandOwner() == inst
end

local function Accessible(inst, station)
    if station == nil or not station:IsValid() or station.prefab ~= "bookstation"
        or station:HasTag("burnt") then return false end
    local c = station.components.container
    local leader = Policy.GetLeader(inst)
    return c ~= nil and not c.readonlycontainer and not c:IsRestricted(inst)
        and (not c:IsOpenedByOthers(inst) or leader ~= nil and c:IsOpenedBy(leader))
        and Policy.InRange(inst, station)
end

local function IsOpen(inst, station)
    local c, leader = station.components.container, Policy.GetLeader(inst)
    return c:IsOpenedBy(inst) or leader ~= nil and c:IsOpenedBy(leader)
end

local function Stations(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local stations = {}
    for _, station in ipairs(TheSim:FindEntities(x, y, z, 20, nil, {"INLIMBO", "burnt"})) do
        if Accessible(inst, station) then stations[#stations + 1] = station end
    end
    table.sort(stations, function(a, b) return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b) end)
    return stations
end

local function CanPickUp(inst, book)
    local ii = book:IsValid() and book.components.inventoryitem or nil
    return ii ~= nil and ii.owner == nil and ii.canbepickedup
        and not book:HasAnyTag("INLIMBO", "burnt", "fire", "outofreach")
        and book.components.book ~= nil and Uses(book) > 0
        and inst:GetCurrentPlatform() == book:GetCurrentPlatform()
        and Policy.InRange(inst, book)
        and inst.components.inventory:CanAcceptCount(book, 1) >= 1
end

local function GroundBooks(inst, target)
    local x, y, z, range = Policy.SearchOrigin(inst, 20)
    local books = {}
    for _, book in ipairs(TheSim:FindEntities(x, y, z, range, {"_inventoryitem"},
        {"INLIMBO", "burnt", "fire"})) do
        if (target == nil or book.prefab == target) and CanPickUp(inst, book) then
            books[#books + 1] = book
        end
    end
    table.sort(books, function(a, b)
        if Uses(a) ~= Uses(b) then return Uses(a) > Uses(b) end
        return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b)
    end)
    return books
end

local function StoreStation(inst, book, stations)
    for _, station in ipairs(stations) do
        local c = station.components.container
        if not c:IsOpenedByOthers(inst) and c:CanTakeItemInSlot(book)
            and c:CanAcceptCount(book, 1) >= 1 then return station end
    end
end

function M.Close(inst, command)
    local station = command ~= nil and command.bookstation or nil
    if station ~= nil and station:IsValid() and station.components.container ~= nil
        and station.components.container:IsOpenedBy(inst) then
        station.components.container:Close(inst)
        inst:PushEvent("closecontainer", {container = station})
    end
    if command ~= nil then command.bookstation = nil end
end

function M.PrepareCommand(inst, command)
    local previous = inst._my_friend_book_request
    command.use_last_book = previous ~= nil and previous.prefab == command.target
        and previous.player == command.player and GetTime() - previous.time <= 30
    inst._my_friend_book_request = {prefab = command.target, player = command.player, time = GetTime()}
end

local function Finish(inst, command)
    M.Close(inst, command)
    if inst._my_friend_command == command then require("my_friend_commands").Clear(inst) end
end

local function StoreAction(inst, station, book, command)
    local action = BufferedAction(inst, station, ACTIONS.MY_FRIEND_STORE, book)
    action.arrivedist = Inventory.ContainerReach(inst, station)
    action._my_friend_close_immediately = true
    action._my_friend_dialogue_kind = "book_store"
    action.validfn = function()
        return (command == nil or inst._my_friend_command == command)
            and Carried(inst, book) and Uses(book) < 2 and Accessible(inst, station)
            and not station.components.container:IsOpenedByOthers(inst)
            and station.components.container:CanAcceptCount(book, 1) >= 1
    end
    return Policy.GuardAction(inst, action)
end

function M.GetReadAction(inst, command)
    local stations, carried, stored = Stations(inst), {}, {}
    for _, book in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if (command.target == nil or book.prefab == command.target)
            and book.components.book ~= nil and Carried(inst, book)
            and Uses(book) > 0 then carried[#carried + 1] = {book = book} end
    end
    for _, station in ipairs(stations) do
        for _, book in pairs(station.components.container.slots or {}) do
            if (command.target == nil or book.prefab == command.target)
                and book.components.book ~= nil and Uses(book) > 0 then
                stored[#stored + 1] = {book = book, station = station}
            end
        end
    end
    local function Healthiest(a, b) return Uses(a.book) > Uses(b.book) end
    table.sort(carried, Healthiest)
    table.sort(stored, Healthiest)
    local chosen = carried[1] or stored[1]
    local ground = GroundBooks(inst, command.target)
    if chosen ~= nil and Uses(chosen.book) < 2
        and stored[1] ~= nil and Uses(stored[1].book) >= 2 then chosen = stored[1] end
    if chosen == nil or Uses(chosen.book) < 2
        and ground[1] ~= nil and Uses(ground[1]) >= 2 then
        local book = ground[1]
        if book ~= nil then
            local action = BufferedAction(inst, book, ACTIONS.PICKUP)
            action._my_friend_dialogue_kind = "book_ground_pickup"
            action.validfn = function()
                return inst._my_friend_command == command and CanPickUp(inst, book)
            end
            return Policy.GuardAction(inst, action)
        end
    end
    if chosen == nil then return end
    local count = #carried + #stored + #ground
    if Uses(chosen.book) < 2 and not command.use_last_book then
        if chosen.station == nil then
            local station = StoreStation(inst, chosen.book, stations)
            if station ~= nil then
                local action = StoreAction(inst, station, chosen.book, command)
                action:AddSuccessAction(function()
                    if count == 1 then
                        Dialogue.Reply(inst, "book_last_stored")
                        Finish(inst, command)
                    end
                end)
                return action
            end
        end
        if stored[1] ~= nil and Uses(stored[1].book) >= 2 then chosen = stored[1]
        elseif count == 1 then
            Dialogue.Reply(inst, chosen.station ~= nil and "book_last_stored" or "book_last_keep")
            Finish(inst, command)
            return
        end
    end
    local book, station = chosen.book, chosen.station
    if station ~= nil then
        command.bookstation = station
        if not IsOpen(inst, station) or inst:GetDistanceSqToInst(station) > Inventory.ContainerReach(inst, station)^2 then
            local action = BufferedAction(inst, station, ACTIONS.MY_FRIEND_OPEN)
            action.arrivedist = Inventory.ContainerReach(inst, station)
            action._my_friend_dialogue_kind = "book_shelf_read"
            action.validfn = function()
                return inst._my_friend_command == command and Accessible(inst, station)
                    and book:IsValid() and book.components.inventoryitem.owner == station
            end
            return Policy.GuardAction(inst, action)
        end
    end
    -- The open action already brought us within reach. A local READ lets
    -- SGwilson use the book's visuals without walking into the solid shelf.
    local action = BufferedAction(inst, nil, ACTIONS.READ, book)
    action._my_friend_dialogue_kind = station ~= nil and "book_shelf_read" or "book_read"
    action.validfn = function()
        if inst._my_friend_command ~= command or not book:IsValid() then return false end
        return station == nil and Carried(inst, book)
            or station ~= nil and Accessible(inst, station)
                and IsOpen(inst, station)
                and book.components.inventoryitem.owner == station
                and inst:GetDistanceSqToInst(station) <= (Inventory.ContainerReach(inst, station) + .5)^2
    end
    action:AddSuccessAction(function()
        if not book:IsValid() then Dialogue.Reply(inst, "book_used_up") end
        Finish(inst, command)
    end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled and inst._my_friend_command == command then
            Dialogue.Reply(inst, "book_read_failed")
            Finish(inst, command)
        else M.Close(inst, command) end
    end)
    return Policy.GuardAction(inst, action)
end

function M.GetStoreAction(inst)
    if inst.prefab ~= "wickerbottom" or inst._my_friend_command ~= nil
        or inst._my_friend_storage_action ~= nil or inst._my_friend_work_target ~= nil
        or inst._my_friend_under_threat or Policy.IsBusy(inst)
        or GetTime() < (inst._my_friend_book_store_after or 0) then return end
    inst._my_friend_book_store_after = GetTime() + 5
    local stations = Stations(inst)
    for _, book in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if book.components.book ~= nil and Carried(inst, book) and Uses(book) < 2 then
            local station = StoreStation(inst, book, stations)
            if station ~= nil then return StoreAction(inst, station, book) end
        end
    end
end

return M
