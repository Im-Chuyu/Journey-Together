local M = {}

-- Same hysteresis radii as vanilla entity activation. This is server-side
-- simulation, not client map revelation or registration as a human player.
M.RADIUS = ENTITY_POPIN_RADIUS or 64
M.RELEASE_RADIUS = ENTITY_POPOUT_RADIUS or M.RADIUS * 1.2
local EXCLUDE = {"INLIMBO"}
local owners = {}
local held = {}

function M.KeepAwake(owner, entity)
    if entity == nil or entity == owner or not entity:IsValid()
        or entity:HasTag("INLIMBO") then return end
    local leases = held[entity]
    if leases == nil then
        -- An asleep entity necessarily allowed sleeping before we touched it.
        -- Never turn a vanilla/mod always-awake entity into a sleepable one.
        if not entity:IsAsleep() then return end
        leases = {}
        held[entity] = leases
    end
    if leases[owner] then return end
    local entities = owners[owner] or {}
    owners[owner] = entities
    entities[entity], leases[owner] = true, true
    entity.entity:SetCanSleep(false)
    -- SetCanSleep(false) prevents the next sleep pass, but an entity that
    -- was already outside the player's active area can still be asleep at
    -- this point. Wake it immediately so pickable plants (including reeds
    -- spawned by a console command) can be found and interacted with.
    if entity.entity.IsAsleep ~= nil and entity.entity:IsAsleep()
        and entity.entity.Wake ~= nil then
        entity.entity:Wake()
    end
end

local function Release(owner, entity)
    owners[owner][entity] = nil
    local leases = held[entity]
    if leases == nil then return end
    leases[owner] = nil
    if next(leases) == nil then
        held[entity] = nil
        -- Let the engine decide whether a real player is still keeping it
        -- awake. Do not manually invoke OnEntitySleep/OnEntityWake callbacks.
        if entity:IsValid() then entity.entity:SetCanSleep(true) end
    end
end

function M.Clear(owner)
    for entity in pairs(owners[owner] or {}) do Release(owner, entity) end
    owners[owner] = nil
end

function M.Update(owner)
    if TheWorld == nil or not TheWorld.ismastersim then return end
    if not owner:IsValid() or not owner:HasTag("my_friend")
        or owner:HasTag("INLIMBO") then
        M.Clear(owner)
        return
    end
    local x, y, z = owner.Transform:GetWorldPosition()
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, M.RADIUS, nil, EXCLUDE)) do
        M.KeepAwake(owner, entity)
    end
    for entity in pairs(owners[owner] or {}) do
        if not entity:IsValid() or entity:HasTag("INLIMBO")
            or owner:GetDistanceSqToInst(entity) > M.RELEASE_RADIUS^2 then
            Release(owner, entity)
        end
    end
end

return M
