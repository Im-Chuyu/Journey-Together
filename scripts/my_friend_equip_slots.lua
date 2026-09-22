local M = {}

function M.IsRegistered(slot)
    if slot == nil then return false end
    for _, value in pairs(EQUIPSLOTS) do
        if value == slot then return true end
    end
    return false
end

function M.All()
    local result, seen = {}, {}
    local function Add(slot)
        if slot ~= nil and not seen[slot] then
            result[#result + 1], seen[slot] = slot, true
        end
    end
    Add(EQUIPSLOTS.HEAD)
    Add(EQUIPSLOTS.BODY)
    Add(EQUIPSLOTS.HANDS)
    local extra = {}
    for _, slot in pairs(EQUIPSLOTS) do
        if not seen[slot] then extra[#extra + 1] = slot end
    end
    table.sort(extra, function(a, b) return tostring(a) < tostring(b) end)
    for _, slot in ipairs(extra) do Add(slot) end
    return result
end

function M.GetBackpack(inventory)
    if inventory == nil then return end
    for _, slot in ipairs(M.All()) do
        local item = inventory:GetEquippedItem(slot)
        if item ~= nil and item:HasTag("backpack") then return item, slot end
    end
end

-- Extra-slot mods may hide overflow from viewers who are not container
-- openers. The companion panel still needs its actual equipped bag.
function M.BackpackContainer(inventory)
    if inventory == nil then return end
    local overflow = inventory.GetOverflowContainer ~= nil and inventory:GetOverflowContainer() or nil
    if overflow ~= nil then return overflow end
    local bag = M.GetBackpack(inventory)
    if bag == nil then return end
    local components = inventory.inst ~= nil and inventory.inst.components or nil
    if components ~= nil and components.inventory == inventory then
        return bag.components.container
    end
    return bag.replica ~= nil and bag.replica.container or nil
end

function M.IsEquipped(inventory, item)
    local eq = item ~= nil and item.components ~= nil and item.components.equippable or nil
    return inventory ~= nil and eq ~= nil
        and inventory:GetEquippedItem(eq.equipslot) == item
end

-- Slot mods sometimes register disabled slots too. Mirror the actual player
-- inventory bar, including its icons, instead of displaying all registrations.
function M.Panel(owner)
    local controls = owner ~= nil and owner.HUD ~= nil and owner.HUD.controls or nil
    local bar = controls ~= nil and controls.inv or nil
    local info = bar ~= nil and bar.equipslotinfo or nil
    local result, seen = {}, {}
    local function Add(slot, atlas, texture)
        if M.IsRegistered(slot) and not seen[slot] then
            result[#result + 1] = {name = slot, atlas = atlas or "images/hud.xml",
                image = texture or (slot == EQUIPSLOTS.HEAD and "equip_slot_head.tex"
                    or slot == EQUIPSLOTS.BODY and "equip_slot_body.tex" or "equip_slot.tex")}
            seen[slot] = true
        end
    end
    for _, slot in ipairs({EQUIPSLOTS.HEAD, EQUIPSLOTS.BODY, EQUIPSLOTS.HANDS}) do
        Add(slot)
    end
    for _, entry in ipairs(info or {}) do Add(entry.slot, entry.atlas, entry.image) end
    for i, entry in ipairs(result) do
        if #result > 3 then
            entry.scale = math.min(1, 5 / #result)
            entry.x = -43.2 + (i - (#result + 1) / 2) * 72 * entry.scale
            entry.y = -146
        else
            entry.x, entry.y = 204, 70 - (i - 1) * 72
        end
    end
    return result
end

-- On a host, classified client methods are absent. An empty authoritative
-- slot must stay empty, not fall through to a client-only method via "or".
function M.ContainerItem(container, slot)
    if container == nil then return end
    local components = container.inst ~= nil and container.inst.components or nil
    if components ~= nil and components.container ~= nil then
        return components.container:GetItemInSlot(slot)
    end
    local classified = container.classified
    if classified ~= nil and classified.GetItemInSlot ~= nil then
        return classified:GetItemInSlot(slot)
    end
    if container.GetItemInSlot ~= nil then return container:GetItemInSlot(slot) end
end

return M
