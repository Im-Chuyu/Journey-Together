local Navigation = require("my_friend_navigation")
local Platforms = require("my_friend_platforms")

local M = {}
-- Native recipes expose spacing rather than the spawned prefab's physics.
local FOOTPRINT = {bookstation = .4, sisturn = .5}
local MAX_PUSH = 3

local function Clearance(recipe, player)
    local footprint = FOOTPRINT[recipe.name] or math.max(.5, (recipe.min_spacing or 3.2) / 2)
    return footprint + player:GetPhysicsRadius(0)
end

function M.Blocker(inst, recipe, point)
    if recipe == nil or recipe.placer == nil or point == nil or Platforms.Surface(point) ~= "land" then return end
    for _, player in ipairs(AllPlayers) do
        if player ~= inst and player:IsValid() and not player:HasTag("playerghost")
            and not player:HasTag("isdead") and player:GetCurrentPlatform() == nil
            and player:GetDistanceSqToPoint(point) < Clearance(recipe, player)^2 then
            return player
        end
    end
end

function M.NativeValid(inst, recipe, point, rotation)
    local map = TheWorld.Map
    return point ~= nil and map ~= nil and map.CanDeployRecipeAtPoint ~= nil
        and not not map:CanDeployRecipeAtPoint(point, recipe, rotation or 0, inst)
end

function M.ActionBlocker(action)
    if action.recipe == nil or action.action ~= ACTIONS.MY_FRIEND_BUILD and action.action ~= ACTIONS.BUILD then return end
    local recipe = GetValidRecipe(action.recipe)
    local point = action:GetActionPoint()
    return M.Blocker(action.doer, recipe, point), recipe, point
end

function M.Build(action)
    local inst, recipe = action.doer, GetValidRecipe(action.recipe)
    if recipe ~= nil and recipe.placer ~= nil then
        local point = action:GetActionPoint()
        if not M.NativeValid(inst, recipe, point, action.rotation) or M.Blocker(inst, recipe, point) ~= nil then
            return false, "placement_blocked"
        end
    end
    return ACTIONS.BUILD.fn(action)
end

function M.PushPoint(inst, recipe, point, player)
    local physics, other = inst.Physics, player.Physics
    if inst:GetCurrentPlatform() ~= nil or physics == nil or other == nil
        or not physics:IsActive() or not other:IsActive()
        or not checkbit(physics:GetCollisionMask(), other:GetCollisionGroup())
        or not checkbit(other:GetCollisionMask(), physics:GetCollisionGroup())
        or inst.components.rider ~= nil and inst.components.rider:IsRiding()
        or player.components.rider ~= nil and player.components.rider:IsRiding()
        or player.sg ~= nil and player.sg:HasStateTag("busy") then return end

    local origin, occupied = inst:GetPosition(), player:GetPosition()
    local dx, dz = occupied.x - origin.x, occupied.z - origin.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance > 24 then return end
    if distance < .01 then
        local angle = inst.Transform:GetRotation() * DEGREES
        dx, dz = math.cos(angle), -math.sin(angle)
    else
        dx, dz = dx / distance, dz / distance
    end
    local ox, oz = occupied.x - point.x, occupied.z - point.z
    local along = ox * dx + oz * dz
    -- Walk along the line of contact until the player's capsule is clear.
    local exit = math.sqrt(math.max(0, (Clearance(recipe, player) + .15)^2 - ox * ox - oz * oz + along * along)) - along
    local contact = physics:GetRadius() + other:GetRadius()
    local push = math.max(.15, exit - contact + .1)
    if push + contact > MAX_PUSH then return end
    local destination = Vector3(occupied.x + dx * push, 0, occupied.z + dz * push)
    local landing = Vector3(destination.x + dx * contact, 0, destination.z + dz * contact)
    if Navigation.InTravelRange(inst, destination)
        and Navigation.IsStepClear(inst, origin, destination, nil, nil, true)
        and Navigation.IsStepClear(player, occupied, landing, nil, nil, true) then
        return destination, distance
    end
end

return M
