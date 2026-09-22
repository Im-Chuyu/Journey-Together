local Policy = require("my_friend_policy")
local Tech = require("my_friend_crafting_tech")
local Dialogue = require("my_friend_dialogue")
local M = {}
local PETS = {
    {"critter_kitten", "浣猫崽", "小浣猫", "小猫", "猫崽", "kittykit"},
    {"critter_puppy", "小座狼", "小狗", "小狼", "vargling"},
    {"critter_lamb", "小钢羊", "钢羊", "小羊", "ewelet"},
    {"critter_perdling", "小火鸡", "火鸡", "giblet"},
    {"critter_dragonling", "小龙蝇", "龙蝇", "小龙", "broodling"},
    {"critter_glomling", "小格罗姆", "格罗姆", "glomglom"},
    {"critter_lunarmothling", "小蛾子", "月蛾", "小蛾", "mothling"},
    {"critter_eyeofterror", "友好窥视者", "窥视者", "小眼球", "眼球", "friendly peeper"},
    {"critter_bulbin", "芽葱", "小葱", "bulbin"},
    {"critter_eets", "一吃", "eets"},
}

function M.Parse(text)
    text = text:lower()
    local requested = false
    for _, verb in ipairs({"领养", "领取", "领一个", "宠物", "adopt"}) do
        if text:find(verb, 1, true) then requested = true break end
    end
    if not requested then return end
    local best, length = false, 0
    for _, entry in ipairs(PETS) do
        local name = STRINGS.NAMES ~= nil and STRINGS.NAMES[string.upper(entry[1])] or nil
        for _, alias in ipairs(entry) do
            if #alias > length and text:find(alias, 1, true) then best, length = entry[1], #alias end
        end
        if type(name) == "string" and #name > length and text:find(name:lower(), 1, true) then
            best, length = entry[1], #name
        end
    end
    return best -- false means an adoption request with an unknown pet name.
end

local function HasRoom(inst)
    local leash = inst.components.petleash
    return leash ~= nil and not leash:IsFull() and not leash:HasPetWithTag("critter")
end

function M.IsIngredient(inst, item)
    local command = inst._my_friend_command
    if command == nil or command.id ~= "adopt_pet" or item == nil then return false end
    local recipe = GetValidRecipe(command.recipe)
    for _, ingredient in ipairs(recipe ~= nil and recipe.ingredients or {}) do
        if item.prefab == ingredient.type then return true end
    end
    return false
end

local function Den(inst, entity)
    return entity ~= nil and entity:IsValid() and entity.prefab == "critterlab"
        and not entity:HasAnyTag("INLIMBO", "burnt", "fire")
        and entity.components.prototyper ~= nil
        and inst:GetCurrentPlatform() == entity:GetCurrentPlatform()
end

local function FindDen(inst, failed)
    local best, distance
    for _, entity in pairs(Ents or {}) do
        if Den(inst, entity) and not failed[entity.GUID] then
            local d = inst:GetDistanceSqToInst(entity)
            if distance == nil or d < distance then best, distance = entity, d end
        end
    end
    return best
end

local function Skin(recipe)
    if not recipe.unlocks_from_skin then return nil, true end
    -- Eets and Bulbin have no unskinned build. Use their registered base
    -- builder skin so vanilla OnBuilt passes the linked skin to the pet.
    for _, skin in ipairs(PREFAB_SKINS ~= nil and PREFAB_SKINS[recipe.product] or {}) do
        if not (PREFAB_SKINS_SHOULD_NOT_SELECT ~= nil and PREFAB_SKINS_SHOULD_NOT_SELECT[skin]) then
            return skin, true
        end
    end
    return nil, false
end

local function Finish(inst, command, reply)
    if inst._my_friend_command ~= command then return end
    require("my_friend_commands").Clear(inst)
    inst._my_friend_follow_requested_until = GetTime() + 30
    Dialogue.Reply(inst, reply)
end

function M.Request(inst, player, prefab)
    if Policy.GetLeader(inst) ~= player or inst:HasTag("playerghost")
        or inst.components.health:IsDead() then return false end
    local recipe = prefab and GetValidRecipe(prefab .. "_builder") or nil
    if recipe == nil then Dialogue.Reply(inst, "pet_unknown") return false end
    if not HasRoom(inst) then Dialogue.Reply(inst, "pet_full") return false end
    local builder = inst.components.builder
    if builder == nil or not builder:HasIngredients(recipe) then
        Dialogue.Reply(inst, "pet_materials") return false
    end
    local skin, available = Skin(recipe)
    if not available then Dialogue.Reply(inst, "pet_unavailable") return false end
    local den = FindDen(inst, {})
    if den == nil then Dialogue.Reply(inst, "pet_no_den") return false end
    require("my_friend_commands").Clear(inst)
    inst._my_friend_command = {id = "adopt_pet", player = player, prefab = prefab,
        recipe = recipe.name, skin = skin, den = den, failed = {}, deadline = GetTime() + 600}
    Dialogue.Reply(inst, "pet_prepare")
    return true
end

function M.GetAction(inst)
    local command = inst._my_friend_command
    if command == nil or command.id ~= "adopt_pet" or Policy.IsBusy(inst) then return end
    local recipe, builder = GetValidRecipe(command.recipe), inst.components.builder
    if not HasRoom(inst) then Finish(inst, command, "pet_full") return end
    if recipe == nil or builder == nil or not builder:HasIngredients(recipe) then
        Finish(inst, command, "pet_materials") return
    end
    if not Den(inst, command.den) then command.den = FindDen(inst, command.failed) end
    local den = command.den
    if den == nil then Finish(inst, command, "pet_no_den") return end
    local action
    if inst:GetDistanceSqToInst(den) > 2^2 then
        action = BufferedAction(inst, den, ACTIONS.WALKTO)
        action.arrivedist = 1.8
        action._my_friend_dialogue_kind = "pet_travel"
    else
        if not Tech.Activate(inst, den, recipe) then Finish(inst, command, "pet_unavailable") return end
        action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD,
            nil, inst:GetPosition(), recipe.name)
        action.skin = command.skin
        action._my_friend_dialogue_kind = "pet_adopt"
        action:AddSuccessAction(function()
            local leash = inst.components.petleash
            local adopted = false
            for pet in pairs(leash:GetPets()) do
                if pet:IsValid() and pet.prefab == command.prefab then adopted = true break end
            end
            Finish(inst, command, adopted and "pet_done" or "pet_unavailable")
        end)
    end
    action._my_friend_roaming = command
    action.validfn = function()
        return inst._my_friend_command == command and Den(inst, den) and HasRoom(inst)
            and builder:HasIngredients(recipe) and (action.action == ACTIONS.WALKTO
                or inst:GetDistanceSqToInst(den) <= 3^2 and den.components.prototyper:CanUsePrototyper(inst)
                    and Tech.CanBuild(inst, recipe))
    end
    action:AddFailAction(function()
        if action._my_friend_cancelled or inst._my_friend_command ~= command then return end
        command.failed[den.GUID], command.den = true, nil
    end)
    return action
end

return M
