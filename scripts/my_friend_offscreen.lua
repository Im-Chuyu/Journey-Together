local LightAI = require("my_friend_light_ai")
local ActiveArea = require("my_friend_active_area")

local M = {}

-- Keep companion-owned critters in the same loaded area as their owner. The
-- vanilla player pet leash performs this recovery for players; companions
-- need the same small safety net because their pets can otherwise remain in
-- an unloaded area indefinitely.
M.PET_RETURN_DISTANCE = 32
M.UPDATE_PERIOD = .5

local function IsAlive(inst)
    return inst ~= nil and inst:IsValid()
        and (inst.components == nil or inst.components.health == nil
            or not inst.components.health:IsDead())
end

local function ReturnPet(owner, pet)
    if not IsAlive(pet) or pet:HasAnyTag("INLIMBO", "playerghost") then return end
    if pet.components == nil or pet.components.follower == nil
        or pet.components.follower:GetLeader() ~= owner then return end
    if owner:GetDistanceSqToInst(pet) <= M.PET_RETURN_DISTANCE ^ 2 then return end

    local x, y, z = owner.Transform:GetWorldPosition()
    local angle = math.random() * 2 * PI
    local offset = FindWalkableOffset ~= nil
        and FindWalkableOffset(Vector3(x, y, z), angle, 2, 8, true, false)
        or nil
    local px, pz = x, z
    if offset ~= nil then px, pz = x + offset.x, z + offset.z end
    if pet.Physics ~= nil and pet.Physics.Teleport ~= nil then
        pet.Physics:Teleport(px, y, pz)
    elseif pet.Transform ~= nil then
        pet.Transform:SetPosition(px, y, pz)
    end
    if pet.sg ~= nil and pet.sg.GoToState ~= nil and pet.sg:HasStateTag("sleeping") then
        pet.sg:GoToState("idle")
    end
    ActiveArea.KeepAwake(owner, pet)
end

function M.Update(inst)
    ActiveArea.Update(inst)
    if not IsAlive(inst) then return end

    -- This runs independently of the companion brain, which may be paused
    -- while the owner is outside the normal player loading range.
    LightAI.UpdateEquipment(inst)

    local leash = inst.components ~= nil and inst.components.petleash or nil
    if leash == nil or leash.GetPets == nil then return end
    for pet in pairs(leash:GetPets()) do ReturnPet(inst, pet) end
end

function M.Configure(inst)
    if TheWorld == nil or not TheWorld.ismastersim then return end
    if inst._my_friend_offscreen_task == nil then
        inst:ListenForEvent("onremove", ActiveArea.Clear)
        inst._my_friend_offscreen_task = inst:DoPeriodicTask(M.UPDATE_PERIOD, M.Update)
        ActiveArea.Update(inst)
    end
end

return M
