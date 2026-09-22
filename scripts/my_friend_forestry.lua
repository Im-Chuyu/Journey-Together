local M = {}

M.TREE_LIMIT = 20
M.BATCH_SIZE = 5
M.SPACING = 8 / 3
M.HALF_SIZE = 10
M.MAX_BASE_DISTANCE = 100

local TREE_SEEDLINGS = {
    pinecone_sapling = true,
    acorn_sapling = true,
    twiggy_nut_sapling = true,
}

local function IsTree(entity)
    return entity:HasTag("tree") or TREE_SEEDLINGS[entity.prefab] == true
end

local function State(inst)
    return inst._my_friend_base
end

local function Distance(a, b)
    return (a.x - b.x)^2 + (a.z - b.z)^2
end

local function Contains(plot, point)
    return math.abs(point.x - plot.x) <= M.HALF_SIZE
        and math.abs(point.z - plot.z) <= M.HALF_SIZE
end

function M.InPlot(inst, entity)
    local state = State(inst)
    local plot = state ~= nil and state.forest or nil
    if plot == nil then return false end
    return Contains(plot, entity:GetPosition())
end

function M.IsUsefulLooseItem(item)
    local c = item.components
    return c.edible ~= nil or c.fertilizer ~= nil or c.tool ~= nil
        or c.equippable ~= nil or c.fuel ~= nil
end

function M.QueueDiscard(inst, prefab, count, plot)
    local queue = inst._my_friend_forest_discard or {}
    inst._my_friend_forest_discard = queue
    for _, entry in ipairs(queue) do
        if entry.prefab == prefab then entry.count = entry.count + count return end
    end
    queue[#queue + 1] = {prefab = prefab, count = count, x = plot.x, z = plot.z}
end

function M.DiscardPoint(inst, entry, base, passable)
    local current = State(inst) ~= nil and State(inst).forest or nil
    for _, radius in ipairs({24, 32, 40}) do
        for direction = 0, 15 do
            local angle = direction * 2 * math.pi / 16
            local point = Vector3(entry.x + math.cos(angle) * radius, 0,
                entry.z + math.sin(angle) * radius)
            if Distance(point, base) > 40^2 and passable(point)
                and (current == nil or not Contains(current, point))
                and not require("my_friend_navigation").IsNearHole(point) then return point end
        end
    end
end

function M.IsMature(tree)
    if tree:HasAnyTag("stump", "burnt", "burning", "monster") then return false end
    local growable = tree.components.growable
    local stage = growable ~= nil and growable.stages ~= nil
        and growable.stages[growable.stage] or nil
    local workable = tree.components.workable
    return stage ~= nil and stage.name == "tall"
        and workable ~= nil and workable:CanBeWorked()
        and workable:GetWorkAction() == ACTIONS.CHOP
end

function M.Points(plot, spacing)
    spacing = spacing or M.SPACING
    local points = {}
    for row = 0, 4 do
        for col = 0, 4 do
            -- Leave a small central aisle in a square 5x5 layout: 20 positions.
            if not (row == 2 and col >= 1 and col <= 3
                or col == 2 and (row == 1 or row == 3)) then
                points[#points + 1] = Vector3(plot.x + (col - 2) * spacing,
                    0, plot.z + (row - 2) * spacing)
            end
        end
    end
    return points
end

function M.Trees(inst)
    local state = State(inst)
    local plot = state ~= nil and state.forest or nil
    local trees = {}
    if plot == nil then return trees end
    for _, tree in ipairs(TheSim:FindEntities(plot.x, 0, plot.z, 15,
        nil, {"INLIMBO", "FX"})) do
        if IsTree(tree) and M.InPlot(inst, tree) then trees[#trees + 1] = tree end
    end
    return trees
end

local function AtManagedPosition(plot, entity)
    if not IsTree(entity) then return false end
    local point = entity:GetPosition()
    for _, planted in ipairs(plot.planted or {}) do
        if Distance(point, planted) < .25 then return true end
    end
    return false
end

function M.CanDigStump(inst, tree)
    local state = State(inst)
    local position = tree:GetPosition()
    for _, point in ipairs(state ~= nil and state.tree_stumps or {}) do
        if Distance(point, position) < 1 then return point.deferred == false end
    end
    return false
end

function M.IsClearanceTarget(inst, target)
    local plot = State(inst) ~= nil and State(inst).forest or nil
    return plot ~= nil and inst._my_friend_forest_clear_target == target
        and M.InPlot(inst, target)
        and (not AtManagedPosition(plot, target) or target:HasAnyTag("stump", "burnt"))
        and not plot.returning
end

function M.RecordPlant(inst, plot, point)
    if State(inst).forest ~= plot then return end
    plot.planted = plot.planted or {}
    for _, planted in ipairs(plot.planted) do
        if Distance(point, planted) < .25 then return end
    end
    plot.planted[#plot.planted + 1] = {x = point.x, z = point.z}
end

local function AdoptLegacyTrees(inst, plot)
    if plot.planted ~= nil then return end
    plot.planted = {}
    -- Older saves planted on a four-unit grid without recording ownership.
    for _, tree in ipairs(M.Trees(inst)) do
        for _, point in ipairs(M.Points(plot, 4)) do
            if Distance(point, tree:GetPosition()) < .25 then
                M.RecordPlant(inst, plot, point)
                break
            end
        end
    end
end

local function ObstacleAction(inst, plot, entity)
    if entity == inst or not entity.entity:IsVisible()
        or entity:HasAnyTag("player", "FX", "DECOR", "INLIMBO", "isdead")
        or entity.components.placer ~= nil
        or entity.entity:GetParent() ~= nil then return end
    if entity:HasAnyTag("structure", "wall", "groundhole", "groundtargetblocker",
        "irreplaceable", "heavy") then return false end
    if entity.components.locomotor ~= nil or entity:HasTag("locomotor") then return end
    if AtManagedPosition(plot, entity) and not entity:HasAnyTag("stump", "burnt") then return end
    local item = entity.components.inventoryitem
    if item ~= nil then
        return item.canbepickedup and not item.islockedinslot and ACTIONS.PICKUP or false
    end
    local workable = entity.components.workable
    if workable ~= nil and workable:CanBeWorked() then
        local action = workable:GetWorkAction()
        if action == ACTIONS.DIG and entity:HasTag("stump") then
            if not M.CanDigStump(inst, entity) then return end
            for _, tool in ipairs(inst.components.inventory:ReferenceAllItems()) do
                if require("my_friend_inventory").IsUsableTool(inst, tool, ACTIONS.DIG) then
                    return action
                end
            end
            return
        end
        if action == ACTIONS.CHOP or action == ACTIONS.DIG or action == ACTIONS.MINE then
            return action
        end
    end
    local pickable = entity.components.pickable
    if entity:HasTag("flower") and pickable ~= nil and pickable.caninteractwith
        and pickable:CanBePicked() then return ACTIONS.PICK end
    if entity:HasTag("NOBLOCK") then return end
    -- A plant that survives picking is not cleared by repeated harvesting.
    return false
end

function M.InspectPlot(inst, plot)
    local work = {}
    for _, entity in ipairs(TheSim:FindEntities(plot.x, 0, plot.z, 15,
        nil, {"INLIMBO", "FX", "DECOR"})) do
        if Contains(plot, entity:GetPosition()) then
            local action = ObstacleAction(inst, plot, entity)
            if action == false then return nil, entity end
            if action ~= nil then work[#work + 1] = {target = entity, action = action} end
        end
    end
    table.sort(work, function(a, b)
        local da, db = inst:GetDistanceSqToInst(a.target), inst:GetDistanceSqToInst(b.target)
        if a.action == ACTIONS.PICKUP then da = da - 1000 end
        if b.action == ACTIONS.PICKUP then db = db - 1000 end
        return da < db
    end)
    return work
end

function M.RejectPlot(inst, plot)
    local state = State(inst)
    if state.forest ~= plot then return end
    state.forest_rejected = state.forest_rejected or {}
    state.forest_rejected[#state.forest_rejected + 1] =
        {x = plot.x, z = plot.z, until_time = GetTime() + 600}
    state.forest = nil
    state.forest_retry_at = 0
    inst._my_friend_forest_clear_target = nil
end

local function GroundSuitable(plot, base, passable, safe)
    -- Keep the whole square, not just its center, inside the 100-unit limit.
    for row = -2, 2 do
        for col = -2, 2 do
            local point = Vector3(plot.x + col * M.HALF_SIZE / 2,
                0, plot.z + row * M.HALF_SIZE / 2)
            if Distance(point, base) > M.MAX_BASE_DISTANCE^2 or not passable(point)
                or not TheWorld.Map:CanPlantAtPoint(point.x, 0, point.z)
                or safe ~= nil and not safe(point) then return false end
        end
    end
    for _, point in ipairs(M.Points(plot)) do
        if not passable(point) or not TheWorld.Map:CanPlantAtPoint(point.x, 0, point.z) then
            return false
        end
    end
    return true
end

function M.EnsurePlot(inst, base, passable, safe)
    local state = State(inst)
    local now = GetTime()
    if state.forest ~= nil then
        local plot = state.forest
        AdoptLegacyTrees(inst, plot)
        if now < (plot.check_at or 0) then return plot end
        plot.check_at = now + 5
        local _, blocker = M.InspectPlot(inst, plot)
        if blocker == nil and GroundSuitable(plot, base, passable) then return plot end
        M.RejectPlot(inst, plot)
    end
    if now < (state.forest_retry_at or 0) then return end
    state.forest_retry_at = now + 60
    local rejected = state.forest_rejected or {}
    for index = #rejected, 1, -1 do
        if now >= rejected[index].until_time then table.remove(rejected, index) end
    end
    for _, radius in ipairs({36, 48, 60, 72, 84}) do
        for direction = 0, 15 do
            local angle = direction * 2 * math.pi / 16
            local candidate = {x = base.x + math.cos(angle) * radius,
                z = base.z + math.sin(angle) * radius, planted = {}}
            local valid = true
            for _, old in ipairs(rejected) do
                if Distance(candidate, old) < (M.HALF_SIZE * 2)^2 * 2 then valid = false break end
            end
            if valid then valid = GroundSuitable(candidate, base, passable, safe) end
            -- Avoid choosing a nearby square on the far side of water.
            if valid then
                for step = 1, math.ceil(radius / 4) do
                    local t = step / math.ceil(radius / 4)
                    if not passable(Vector3(base.x + (candidate.x - base.x) * t,
                        0, base.z + (candidate.z - base.z) * t)) then valid = false break end
                end
            end
            if valid then
                local _, blocker = M.InspectPlot(inst, candidate)
                if blocker == nil then
                    candidate.check_at = now + 5
                    state.forest = candidate
                    return candidate
                end
            end
        end
    end
end

function M.FindPlantPoint(inst, item, passable)
    local plot = State(inst).forest
    if plot == nil then return end
    local work, blocker = M.InspectPlot(inst, plot)
    if blocker ~= nil then M.RejectPlot(inst, plot) return end
    if #work > 0 then return end
    local trees = M.Trees(inst)
    if #trees >= M.TREE_LIMIT then return end
    plot.blocked = plot.blocked or {}
    local tried = false
    for index, point in ipairs(M.Points(plot)) do
        local occupied = false
        for _, tree in ipairs(trees) do
            if Distance(point, tree:GetPosition()) < 4 then occupied = true break end
        end
        if not occupied and GetTime() >= (plot.blocked[index] or 0) then
            tried = true
            if passable(point) and item.components.deployable:CanDeploy(point, nil, inst, 0) then
                plot.unplantable_since = nil
                return point, index
            end
        end
    end
    if tried then
        plot.unplantable_since = plot.unplantable_since or GetTime()
        if GetTime() - plot.unplantable_since >= 30 then M.RejectPlot(inst, plot) end
    end
end

function M.GetBatchTarget(inst, allowed, can_start)
    local plot = State(inst).forest
    if plot == nil or plot.returning then return end
    local mature = {}
    for _, tree in ipairs(M.Trees(inst)) do
        if M.IsMature(tree) and allowed(tree) then mature[#mature + 1] = tree end
    end
    table.sort(mature, function(a, b)
        return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b)
    end)
    if plot.batch == nil and can_start and #mature >= M.BATCH_SIZE then
        plot.batch = {}
        for index = 1, M.BATCH_SIZE do
            local point = mature[index]:GetPosition()
            plot.batch[#plot.batch + 1] = {x = point.x, z = point.z}
        end
    end
    if plot.batch == nil then return end
    for index = #plot.batch, 1, -1 do
        local point = plot.batch[index]
        for _, tree in ipairs(mature) do
            if Distance(point, tree:GetPosition()) < 1 then return tree end
        end
        table.remove(plot.batch, index)
    end
    plot.batch = nil
    plot.returning = true
end

function M.RecordChop(inst, tree, point, deferred)
    local state = State(inst)
    if state == nil then return end
    if tree:IsValid() and tree:HasTag("stump") then
        state.tree_stumps = state.tree_stumps or {}
        local found
        for _, old in ipairs(state.tree_stumps) do
            if Distance(point, old) < 1 then found = old break end
        end
        if found == nil then
            found = {x = point.x, z = point.z}
            state.tree_stumps[#state.tree_stumps + 1] = found
        end
        -- Decide at felling time, before later crafting can change the inventory.
        found.deferred = deferred ~= false
    end
    local plot = state.forest
    if plot ~= nil and plot.batch ~= nil then
        for index = #plot.batch, 1, -1 do
            if Distance(point, plot.batch[index]) < 1 then table.remove(plot.batch, index) end
        end
        if #plot.batch == 0 then plot.batch = nil plot.returning = true end
    end
end

function M.GetStump(inst, allowed)
    local state = State(inst)
    for index = #(state.tree_stumps or {}), 1, -1 do
        local point = state.tree_stumps[index]
        local found
        for _, tree in ipairs(TheSim:FindEntities(point.x, 0, point.z,
            1, {"stump"}, {"INLIMBO"})) do
            local workable = tree.components.workable
            if workable ~= nil and workable:CanBeWorked()
                and workable:GetWorkAction() == ACTIONS.DIG then
                found = tree
                if point.deferred == false and allowed(tree) then return tree end
            end
        end
        if found == nil then table.remove(state.tree_stumps, index) end
    end
end

function M.OnSave(inst)
    local state = State(inst)
    local plot = state.forest
    return plot ~= nil and {x = plot.x, z = plot.z, batch = plot.batch,
        returning = plot.returning, planted = plot.planted} or nil
end

local function ValidPoint(point)
    return type(point) == "table" and type(point.x) == "number" and type(point.z) == "number"
        and point.x == point.x and point.z == point.z
        and math.abs(point.x) < math.huge and math.abs(point.z) < math.huge
end

function M.OnLoad(inst, saved)
    local state = State(inst)
    state.tree_stumps = {}
    for _, point in ipairs(type(saved.tree_stumps) == "table" and saved.tree_stumps or {}) do
        if ValidPoint(point) then
            state.tree_stumps[#state.tree_stumps + 1] = {
                x = point.x, z = point.z, deferred = point.deferred ~= false,
            }
        end
    end
    if ValidPoint(saved.forest) then
        state.forest = {x = saved.forest.x, z = saved.forest.z,
            returning = saved.forest.returning == true}
        if type(saved.forest.planted) == "table" then
            state.forest.planted = {}
            for _, point in ipairs(saved.forest.planted) do
                if ValidPoint(point) and Contains(state.forest, point) then
                    state.forest.planted[#state.forest.planted + 1] = {x = point.x, z = point.z}
                end
            end
        end
        if type(saved.forest.batch) == "table" then
            state.forest.batch = {}
            for _, point in ipairs(saved.forest.batch) do
                if ValidPoint(point) and #state.forest.batch < M.BATCH_SIZE then
                    state.forest.batch[#state.forest.batch + 1] = {x = point.x, z = point.z}
                end
            end
        end
    end
end

return M
