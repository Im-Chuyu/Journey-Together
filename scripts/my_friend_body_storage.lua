local Inventory = require("my_friend_inventory")
local M = {}

-- Shadow chests share an off-map container. Only their physical openings
-- are valid interaction targets.
function M.Resolve(target)
    if target == nil or not target:IsValid() then return end
    local proxy = target.components.container_proxy
    local owner = target
    if proxy ~= nil then owner = proxy:GetMaster()
    elseif target:HasTag("pocketdimension_container") then return end
    if owner == nil or not owner:IsValid() then return end
    local container = owner.components.container
    if container ~= nil then return container, owner, proxy or container end
end

function M.Accessible(inst, target)
    local container, owner, opening = M.Resolve(target)
    if container == nil or not Inventory.CanWithdrawFrom(inst, owner) then return false end
    return opening == container or opening:CanBeOpened()
        and not target:HasTag("burnt") and not target:IsInLimbo()
end

return M
