local Behaviour = require("my_friend_behavior_ai")
local Navigation = require("my_friend_navigation")
local M = {}

function M.IsSafe(inst, point)
    if not Navigation.IsLand(point) or Navigation.IsBlocked(inst, point) then return false end
    for _, entity in ipairs(TheSim:FindEntities(point.x, 0, point.z, 12, nil,
        {"INLIMBO", "FX", "playerghost"})) do
        if entity ~= inst then
            local p = entity:GetPosition()
            local distance = (point.x - p.x)^2 + (point.z - p.z)^2
            local c = entity.components
            local burn = c.burnable
            local propagator = c.propagator
            if Behaviour.IsThreat(inst, entity) then return false end
            if entity:HasTag("lava") and distance < 8^2
                or burn ~= nil and burn:IsBurning() and not entity:HasTag("campfire") and distance < 5^2
                or propagator ~= nil and propagator.damages
                    and entity.prefab == "fire" and distance < ((propagator.damagerange or 3) + 2)^2 then
                return false
            end
            -- Be more cautious with the creature responsible for the last death,
            -- not every neutral creature in the region.
            --
            -- Players are never remembered as killers. A player who killed the
            -- companion is usually the same one who revives it, and then stands
            -- over the corpse and the dropped bag while giving orders. Treating
            -- them as a hazard put an unreachable six unit bubble around them
            -- for the rest of the world's life, so every "捡个背包"/"换个背包"
            -- was vetoed by GetAction and died without a word. A player who is
            -- still actually swinging is caught by the IsThreat test above.
            local site = inst._my_friend_death_point
            local near_death = site ~= nil and (site.x - point.x)^2 + (site.z - point.z)^2 < 20^2
            local remembered_killer = not entity:HasTag("player")
                and (entity == inst._my_friend_death_attacker
                    or inst._my_friend_death_attacker == nil and near_death
                        and entity.prefab == inst._my_friend_death_attacker_prefab)
            if c.combat ~= nil and c.health ~= nil and not c.health:IsDead()
                and remembered_killer
                and distance < math.max(6, c.combat:GetAttackRange() + 2)^2 then return false end
        end
    end
    return true
end

return M
