-- 伙伴自动躲避的攻击动画、危险帧和移动参数。
local M = {}

local function Radius(entity)
    return entity.GetPhysicsRadius ~= nil and entity:GetPhysicsRadius(0) or 0
end

function M.AttackRange(entity)
    local combat = entity.components ~= nil and entity.components.combat or nil
    return combat ~= nil and (combat.GetAttackRange ~= nil and combat:GetAttackRange()
        or combat.attackrange or combat.hitrange or 2) or 2
end

function M.Speed(inst)
    local locomotor = inst.components.locomotor
    return locomotor ~= nil and (locomotor.GetRunSpeed ~= nil and locomotor:GetRunSpeed()
        or locomotor.runspeed or 6) or 6
end

function M.Value(value, fallback, ...)
    if type(value) ~= "function" then return value ~= nil and value or fallback end
    local ok, result = pcall(value, ...)
    return ok and result ~= nil and result or fallback
end

function M.Create(inst)
    local DEGREES, FRAMES = math.pi / 180, 1 / 30
    local function distsq(a, b) return (a.x - b.x)^2 + (a.z - b.z)^2 end
    local function ResolveValue(value, ...) return M.Value(value, nil, ...) end
    local function AttackRange(entity) return M.AttackRange(entity) end
    local scans = setmetatable({}, {__mode = "k"})
    local function FindEntity(entity, range, fn)
        local p = entity:GetPosition()
        scans[entity] = scans[entity] or {}
        local cached, now = scans[entity][range], GetTime()
        if cached == nil or now >= cached.until_time or distsq(p, cached.position) > 1 then
            local items = TheSim:FindEntities(p.x, 0, p.z, range, nil, {"INLIMBO", "DECOR"})
            cached = {items = setmetatable(items, {__mode = "v"}), count = #items,
                position = {x = p.x, z = p.z}, until_time = now + .25}
            scans[entity][range] = cached
        end
        for index = 1, cached.count do
            local candidate = cached.items[index]
            if candidate ~= nil and candidate ~= entity and candidate:IsValid() and fn(candidate) then return candidate end
        end
    end
    local EntityHelpers = {}
    function EntityHelpers:GetAngle(entity, other)
        if entity.GetAngleToPoint == nil or entity.Transform == nil then return 0 end
        return math.abs((entity.Transform:GetRotation() - entity:GetAngleToPoint(other:GetPosition()) + 180) % 360 - 180)
    end
    function EntityHelpers:CheckDebugString(entity, ...)
        for _, animation in ipairs({...}) do
            if entity.AnimState ~= nil and entity.AnimState:IsCurrentAnimation(animation)
                or entity.sg ~= nil and entity.sg.currentstate ~= nil
                    and entity.sg.currentstate.name == animation then return true end
        end
        return false
    end
    local profiles = {targetanimtable = {}, PC = {CanLocomote = function() return true end}}
    function profiles:ResetScanCache() scans = setmetatable({}, {__mode = "k"}) end
    function profiles:GetSpeed() return M.Speed(inst) end
    function profiles:GetTargetCanHitRange(entity, other) return AttackRange(entity) + Radius(other) end
    local function calculate(entity, startframe, stopframe, _, data)
        data = data or {}
        local distance = math.sqrt(distsq(entity:GetPosition(), inst:GetPosition()))
        local maximum = ResolveValue(data.dist, entity)
            or (profiles:GetTargetCanHitRange(entity, inst) * (data.combat_scale or 1)
                + (data.calculate_offset or .4) + .1 + (data.extradist or 0)
                + (ResolveValue(data.combat_offset, entity) or 0))
        local speed = math.max(.5, math.min(10, M.Speed(inst) - 1))
        return (data._b or stopframe) - 30 * (data.mod_anim and 4 / 3 or 1)
            * (maximum - distance) / speed
    end
    local special_mod_anim_mult, walk_start_framge, safeadvance = 4 / 3, 5, 2
    local function addcreature(prefab, atkanim, atk_frame_calculate, atk_start_frame, atk_stop_frame, dodgeaimpos, data)
        data = data or {}
        if not profiles.targetanimtable[prefab] then profiles.targetanimtable[prefab] = {} end
        table.insert(profiles.targetanimtable[prefab], {
            atkanim = atkanim,
            atk_frame_calculate = atk_frame_calculate,
            atk_start_frame = atk_start_frame,
            atk_stop_frame = atk_stop_frame,
        })
        if dodgeaimpos then
            for k, v in pairs(dodgeaimpos) do
                profiles.targetanimtable[prefab][#profiles.targetanimtable[prefab]][k] = v
            end
        end

        for k, v in pairs(data) do
            profiles.targetanimtable[prefab][#profiles.targetanimtable[prefab]][k] = v
        end
    end
    local function addcreaturedata(prefab, data)
        data = data or {}
        if not profiles.targetanimtable[prefab] then profiles.targetanimtable[prefab] = {} end
        table.insert(profiles.targetanimtable[prefab], {})

        for k, v in pairs(data) do
            profiles.targetanimtable[prefab][#profiles.targetanimtable[prefab]][k] = v
        end
    end
    local function copy(a, b)
        profiles.targetanimtable[a] = profiles.targetanimtable[b]
    end
    local function makeNoUsed(prefab)
        addcreature(prefab, 'run_loop', calculate, -1, -1, nil, { noused = true })
    end
    addcreature('tallbird', 'atk_pre', calculate, 0, 12, nil, {
        idledodge = function(ent)
            local distance = math.sqrt(distsq(ent:GetPosition(), inst:GetPosition()))
            local min = ent:GetPhysicsRadius(0) + inst:GetPhysicsRadius(0)
            return distance - min < 1 and (profiles.PC:CanLocomote() and 52 or 44) or 2000
        end,
    })
    addcreature('tallbird', 'atk', nil, 0, 2)
    addcreature('krampus', 'atk_pre', nil, 0, 18)
    addcreature('krampus', 'atk', nil, 0, 3)

    addcreature('rocky', 'atk', calculate, 0, 20)
    addcreature('minotaur', 'bite', calculate, 0, 16, nil, { combat_offset = 1 })
    addcreature('minotaur', 'jump_atk_loop', nil, 0, 20,
        { point = "target", update = false, angle = 180 * DEGREES, dist = 2 })
    addcreature('tentacle', 'hit', nil, 0, 20)
    addcreature('tentacle', 'atk_loop', nil, 0, 30)

    addcreature('deerclops', 'atk', nil, (16 - 2) or 10, 33 + 3 - 1, {
        point = "player",
        update = false,
        angle = -80 * DEGREES,
        dist = 6,
    })
    addcreature("bearger", 'atk', nil, 0 or (10 - 3), 32, {
        point = "target", update = false, angle = 90 * DEGREES, dist = 2.1 }, {
        breakdodgefn = function(ent)
            return EntityHelpers:GetAngle(ent, inst) > 70
        end,
    })
    addcreature("bearger", 'ground_pound', nil, 0, (20 + 0.6 / FRAMES) or 20, {
        point = "target", update = true, angle = 0 * DEGREES, dist = 1 + 2 * 3 })
    addcreature("mutatedbearger", 'ground_pound', nil, 0, (20 + 0.6 / FRAMES) or 20, {
        point = "target", update = true, angle = 0 * DEGREES, dist = 1 + 2 * 3 })
    addcreature("mutatedbearger", 'atk1', nil, 0, 32,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 60
            end,
        })
    addcreature("mutatedbearger", 'atk2', nil, 0, 32,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 60
            end,
        })
    addcreature("mutatedbearger", 'atk1a', nil, 0, 32,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 60
            end,
        })
    addcreature("mutatedbearger", 'butt_pre_L', nil, 0, 32,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) < 120
            end,
        })
    addcreature("mutatedbearger", 'butt_pre_R', nil, 0, 32,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) < 120
            end,
        })

    addcreature("mutatedbearger", 'butt_pst', nil, 0, (2 + 0.6 / FRAMES - 10),
        { point = "target", update = true, angle = 0, dist = 1 + 2 * 3 })
    addcreature("mutatedbearger", 'butt', nil, 0, 10,
        { point = "target", update = true, angle = 0, dist = 1 + 2 * 3 })

    addcreature('dragonfly', 'atk', function(ent)
        local distance = math.sqrt(distsq(ent:GetPosition(), inst:GetPosition()))
        local min = ent:GetPhysicsRadius(0) + inst:GetPhysicsRadius(0)
        if ent.AnimState:GetBuild() == "dragonfly_fire_build" then return 17 end

        return distance - min < 1.4 and 17 or 0
    end, 0, 15, nil, {
        idledodge = function(ent)
            if ent.AnimState:GetBuild() == "dragonfly_fire_build" then
                return 1000000
            end

            local distance = math.sqrt(distsq(ent:GetPosition(), inst:GetPosition()))
            local min = ent:GetPhysicsRadius(0) + inst:GetPhysicsRadius(0)
            if distance - min < 1.4 then
                return calculate(ent, 95, 120, true, profiles.targetanimtable.dragonfly[1])

            end
            return 1000000
        end,
        breakdodgefn = function(ent)
            if EntityHelpers:CheckDebugString(ent, 'sleep_loop', 'hit_ground', 'vomit', 'hit_large') then
                return true
            end
        end,
        combat_offset = function(dragon)
            return dragon.AnimState:GetBuild() == "dragonfly_fire_build" and 2 or 1
        end,

    })
    addcreature('dragonfly', 'taunt_pre', calculate, 0, 18 + 2, {
        point = "target", update = true, angle = 0 * DEGREES, dist = 1.5 + 2 * 2 + 1 })
    addcreature('dragonfly', 'taunt', nil, 0, 20 + 0.6 / FRAMES, {
        point = "target", update = true, angle = 0 * DEGREES, dist = 1.5 + 2 * 2 + 1 })
    addcreature("klaus", 'attack_doubleclaw', nil, 0, 26, nil, { combat_scale = 4 / 3 })
    addcreature("klaus", 'attack_chomp', nil, 10 - walk_start_framge, 25 - walk_start_framge, {
        point = "target",
        update = true,
        angle = 0 * DEGREES,
        dist = 0
    })
    addcreature("klaus", 'attack_chomp', nil, 26 - walk_start_framge, 49 or 35, nil, { combat_scale = 4 / 3 })
    addcreature("leif", 'atk', calculate, 0, 25)
    addcreature("leif_sparse", 'atk', calculate, 0, 25)
    addcreature('stalker', 'attack', calculate, 0, 32,
        { point = "target", update = true, angle = 0, extradist = 1.4 })
    addcreature('stalker', 'spikes', calculate, 0, 51,
        { point = "target", update = true, angle = 0, extradist = 1.4 })
    addcreature('stalker', 'attack1', calculate, 0, 25,
        { point = "target", update = true, angle = 0, extradist = 1.4 })
    copy('stalker_atrium', 'stalker')
    copy('stalker_forest', 'stalker')

    addcreature('knight_nightmare', 'atk', calculate, 0, 17, nil, {
        combat_offset = 0.25,
    })
    addcreature('knight', 'atk', calculate, 0, 17, nil, {
        combat_offset = 0.25,
    })
    addcreature('pigman', 'atk', calculate, 0, 13)
    addcreature('pigman', 'idle_angry', nil, 0, 20)
    addcreature('pigman', 'counter_atk', nil, 0, 9 * special_mod_anim_mult, { mod_anim = true, })
    copy('pigguard', 'pigman')
    addcreature('moonpig', 'were_atk_pre', calculate, 0, 10)
    addcreature('moonpig', 'were_atk', nil, 0, 2)
    addcreature('merm', 'atk', calculate, 0, 13)
    addcreature('mermguard', 'atk', calculate, 0, 13)
    addcreature('bunnyman', 'atk', calculate, 0, 13)
    addcreature('rabbitkingminion_bunnyman', 'atk', nil, 0, 13)
    addcreature('lordfruitfly', 'atk', calculate, 0, 8)
    addcreature('koalefant_summer', 'atk', calculate, 0, 10)
    addcreature('koalefant_winter', 'atk', calculate, 0, 10)

    addcreature('moose', 'atk', calculate, 0, 20)
    addcreature('moose', 'hopatk', nil, 30, 42,
        { update = false, angle = 90 * DEGREES, dist = 2 })
    addcreature('moose', 'hopatk_loop', nil, 0, 42)
    addcreature('malbatross', 'atk', calculate, 0, 29)
    addcreature('fused_shadeling', 'attack', calculate, 0, 14)
    addcreature('frog', 'atk', nil, 0, 8)
    addcreature('frog', 'atk_pre', calculate, 0, 22)
    addcreature('lunarfrog', 'atk', nil, 0, 8)
    addcreature('lunarfrog', 'atk_pre', calculate, 0, 22)
    addcreature('worm', 'atk', calculate, 0, 25)
    addcreature('yots_worm', 'atk', calculate, 0, 25)
    addcreature('spiderqueen', 'atk', calculate, 0, 28)
    addcreature('fruitdragon', 'attack', calculate, 0, 22, nil,
        { combat_offset = TUNING.FRUITDRAGON.HIT_RANGE - TUNING.FRUITDRAGON.ATTACK_RANGE })
    copy('wormwood_fruitdragon', 'fruitdragon')
    addcreature('catcoon', 'atk', nil, 0, 16)
    copy('ticoon', 'catcoon')
    addcreature('daywalker', 'atk_slam_pre', nil, 10, 30,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 })
    addcreature('daywalker', 'atk_slam', nil, 0, 10,
        { point = "target", update = false, angle = 90 * DEGREES, dist = 2 })
    addcreature('daywalker', 'run_pre', nil, 0, 30,
        { update = false, angle = 80 * DEGREES, dist = 4, }, { checkatktag = true })
    addcreature('daywalker', 'run_loop', nil, 0, 30,
        { update = true, angle = 0 * DEGREES, dist = 8, }, {})
    addcreature('daywalker', 'atk3', nil, 0, 12,
        { point = "target", update = true, angle = 80 * DEGREES, dist = 5, })
    addcreature('chest_mimic_revealed', 'attack', nil, 0, 18)
    addcreature('fruitfly', 'atk', nil, 0, 8)
    addcreature('merm_shadow', 'atk', calculate, 0, 13)
    addcreature('merm_lunar', 'atk', calculate, 0, 13)
    addcreature('shadowthrall_horns', 'slap', nil, 0, 42)
    addcreature('shadowthrall_horns', 'jump', nil, 0, 30,
        { point = "target", update = false, angle = 180 * DEGREES, dist = 2 })
    addcreature('shadowthrall_wings', 'cast', nil, 23, 100,
        { point = "target", update = false, angle = 120 * DEGREES, dist = 2 })
    addcreature('eyeplant', 'atk', calculate, 0, 14)
    addcreature('hound_common', 'atk_pre', calculate, 0, 16)
    addcreature('hound_common', 'atk', nil, 0, 2)
    copy('hound', 'hound_common')
    copy('firehound', 'hound_common')
    copy('icehound', 'hound_common')
    copy('moonhound', 'hound_common')
    copy('clayhound', 'hound_common')
    copy('mutatedhound', 'hound_common')
    copy('hedgehound', 'hound_common')
    copy('warglet', 'hound_common')
    addcreature('otter', 'bite', calculate, 0, 15)
    addcreature('molebat', 'attack', calculate, 0, 10)
    addcreature('eyeofterror_mini', 'atk_pre', calculate, 0, 14,
        { point = "target", update = true, })
    addcreature('eyeofterror_mini', 'atk', nil, 0, 4,
        { point = "target", update = true, })

    addcreature('crabking_claw', 'atk', nil, 0, 24)
    addcreature('ruinsnightmare', 'atk_walk_pre', nil, 0, 16)
    addcreature('ruinsnightmare', 'atk_pre', nil, 0, 16)
    addcreature('ruinsnightmare', 'atk', nil, 0, 10)
    addcreature('slurtle', 'atk', nil, 0, 10)

    addcreature('shark', 'attack', nil, 0, 26)
    addcreature('powder_monkey', 'unequipped_atk', nil, 0, 14)
    addcreature('powder_monkey', 'atk', nil, 0, 14)
    addcreature('oceanhorror', 'atk_pre', calculate, 0, 17)
    addcreature('oceanhorror', 'atk', nil, 0, 17 - 10)
    addcreature('spat', 'snot_pre', nil, 0, 27 + 4,
        { point = "target", update = true, angle = 180 * DEGREES, dist = 2 })
    addcreature('spat', 'snot', nil, 0, 30,
        { point = "target", update = true, angle = 180 * DEGREES, dist = 2 })
    addcreature('crabking_mob', 'atk1', calculate, 0, 18)
    copy('crabking_mob_knight', 'crabking_mob')
    addcreature('deer', 'atk', calculate, 0, 12)
    copy('deer_red', 'deer')
    copy('deer_blue', 'deer')
    addcreature('daywalker2', 'atk_object', nil, 0, 16,
        { point = "target", update = true, angle = 0 * DEGREES, dist = 7 })

    addcreature('archive_centipede', 'atk', calculate, 0, 9)
    addcreature('archive_centipede', 'atk_aoe', calculate, 0, 25,
        { point = "target", update = true, angle = 0 * DEGREES, extradist = 1 })
    addcreature('squid', 'attack', nil, 0, 26)
    addcreature('snurtle', 'atk', calculate, 0, 10)
    addcreature('bat', 'atk', calculate, 0, 11)
    addcreature('smallbird', 'atk', calculate, 0, 12)
    addcreature('mermguard_lunar', 'atk', calculate, 0, 13)
    addcreature('mermguard_shadow', 'atk', calculate, 0, 13)
    addcreature('beeguard', 'atk', calculate, 0, 13)
    makeNoUsed('beequeen')
    makeNoUsed('crabking')
    makeNoUsed('sharkboi')
    makeNoUsed('rook')
    makeNoUsed('sandspike')
    makeNoUsed('bird_mutant')
    makeNoUsed('bird_mutant_spitter')
    makeNoUsed('prime_mate')
    addcreature('penguin', 'atk', calculate, 0, 8)
    copy('mutated_penguin', 'penguin')
    local alterguardian_phase1_dodge1 = {
        point = "target",
        update = true,
        angle = 0,
        dist = TUNING
            .ALTERGUARDIAN_PHASE1_AOERANGE + 0.7
    }
    addcreature('alterguardian_phase1', 'tantrum_pre', calculate, 0, 26, alterguardian_phase1_dodge1)
    addcreature('alterguardian_phase1', 'tantrum_loop', nil, 0, 20, alterguardian_phase1_dodge1)
    addcreature('alterguardian_phase1', 'tantrum_pst', nil, 0, 8, alterguardian_phase1_dodge1)
    addcreature('alterguardian_phase1', 'roll_pre', nil, 20, 51,
        { point = "target", update = true, angle = -90 * DEGREES, dist = 4 })
    addcreature('alterguardian_phase1', 'roll_loop', nil, 0, 100,
        {
            point = "player",
            update = true,
            angle = function(target)
                if EntityHelpers:GetAngle(target, inst) > 90 then
                    return 0 * DEGREES
                end
                return 90 * DEGREES
            end,
            dist = function(target)
                if EntityHelpers:GetAngle(target, inst) > 90 then
                    return math.sqrt(distsq(target:GetPosition(), inst:GetPosition())) - 10
                end
                return 4
            end,
        })
    addcreature('alterguardian_phase1', 'roll_pst', nil, 0, 18, alterguardian_phase1_dodge1)
    copy('alterguardian_phase1_lunarrift', 'alterguardian_phase1')
    local a_p_2_1, a_p_2_2 = 18, 4.5
    addcreature('alterguardian_phase2', 'attk_spin_pre', nil, 0, 38,
        { point = "target", update = true, angle = 0 * DEGREES, dist = 20 })
    addcreature('alterguardian_phase2', 'attk_spin_loop', nil, 0, 100,
        { point = "target", update = true, angle = 0 * DEGREES, dist = 20 })
    addcreature('alterguardian_phase2', 'attk_spin_pst', nil, 0, 10,
        { point = "target", update = true, angle = 0 * DEGREES, dist = 6 })
    addcreature('alterguardian_phase2', 'attk_stab_pre', calculate, 0, 28, nil, { combat_offset = a_p_2_2 - a_p_2_1 })
    addcreature('alterguardian_phase2', 'attk_chop', function(ent, a, b, notdelay, v, ...)
            local alterguardian_summon_fx = FindEntity(ent, 1, function(t)
                return t.prefab == "alterguardian_summon_fx"
            end)
            if alterguardian_summon_fx then
                return 0
            end
            return calculate(ent, a, b, notdelay, v, ...)
        end, 0, function(ent)
            local alterguardian_summon_fx = FindEntity(ent, 1, function(t)
                return t.prefab == "alterguardian_summon_fx"
            end)
            if alterguardian_summon_fx then
                return 100
            end
            return 23
        end,
        {
            point = "target",
            update = true,
            angle = 0,
            dist = function(ent)
                local alterguardian_summon_fx = FindEntity(ent, 1, function(t)
                    return t.prefab == "alterguardian_summon_fx"
                end)
                if alterguardian_summon_fx then
                    local range = TUNING.ALTERGUARDIAN_PROJECTILE_SPEED / 0.75 * 10 * FRAMES - 2
                    local smallguard_alterguardian_projectile = FindEntity(inst, range, function(t)
                        return t.prefab == "smallguard_alterguardian_projectile"
                            and not t.AnimState:IsCurrentAnimation("mutate")
                    end)
                    if smallguard_alterguardian_projectile then
                        return 40
                    else
                        return math.max(a_p_2_2 + 1, math.sqrt(-4 + distsq(ent:GetPosition(), inst:GetPosition())))
                    end
                end
            end
        },
        { combat_offset = a_p_2_2 - a_p_2_1 })

    addcreature('alterguardian_phase3', 'attk_stab2_pre', nil, 0, 100, nil, { combat_offset = 7 })
    addcreature('alterguardian_phase3', 'attk_stab2_loop', nil, 0, 100, nil, { combat_offset = 7 })
    addcreature('alterguardian_phase3', 'attk_stab', calculate, 0, 45, nil,
        {
            combat_offset = 2 - 14,
            calculate_offset = 1,
            breakdodgefn = function(ent)
                return profiles.p_range == 4 and profiles.distance > 3
            end,
            _b = 29,
        })
    local SECOND_BLAST_TIME = 28
    addcreature('alterguardian_phase3', 'attk_beam', nil, 0, 21,
        {
            point = "target",
            update = true,
            angle = 0 * DEGREES,
            dist = 10,
        })
    addcreature('alterguardian_phase3', 'attk_beam', nil, 21, 35 + SECOND_BLAST_TIME,
        {
            point = "player",
            update = false,
            angle = 90 * DEGREES,
            dist = 2,
        })
    addcreature('alterguardian_phase3', 'attk_swipe', nil, 0, 21,
        {
            point = "target",
            update = true,
            angle = 0 * DEGREES,
            dist = 10,
        })
    addcreature('alterguardian_phase3', 'attk_swipe', nil, 21, 37 + SECOND_BLAST_TIME,
        {
            point = "player",
            update = false,
            angle = 0 * DEGREES,
            dist = -2,
        })

    addcreature('alterguardian_phase4_lunarrift', 'dash_pre', nil, 0, 100,
        {
            point = "target",
            update = true,
            angle = 0 * DEGREES,
            dist = 12,
        })
    addcreature('alterguardian_phase4_lunarrift', 'dash_loop', nil, 0, 100,
        {
            point = "player",
            update = true,
            angle = 135 * DEGREES,
            dist = 4,
        }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 145
            end,
        })
    addcreature('alterguardian_phase4_lunarrift', 'slam', calculate, 0, 44, nil, { combat_offset = 4 })
    addcreature('alterguardian_phase4_lunarrift', 'slam', nil, 44, 77, nil, { combat_offset = 4 })

    addcreature('wagboss_robot', 'atk_squish', calculate, 0, 27, nil, {})
    addcreature('wagboss_robot', 'atk_squish', nil, 27, 30, nil, {})
    addcreature('wagboss_robot', 'taunt2_loop', calculate, 0, 25, nil, {})
    addcreature('wagboss_robot', 'taunt2_loop', nil, 25, 32, nil, {})

    addcreature('wagboss_robot', 'atk_leap_pre', nil, 55, 62, nil, { update = false, dist = -8, legacypos = true })
    addcreature('wagboss_robot', 'atk_leap', nil, 0, 100, nil, { update = false, dist = -8, legacypos = true })
    addcreature('wagboss_robot', 'atk_leap_pst', nil, 0, 7, nil, { update = false, dist = -8 })

    addcreature('wagboss_robot', 'atk_missile_pre1', nil, 0, 100, nil, {
        dist = 20,
    })
    addcreature('wagboss_robot', 'atk_missile_pre2', nil, 0, 100, nil, { dist = 20 })
    addcreature('wagboss_robot', 'atk_missile_hit', nil, 0, 100, nil, { dist = 20 })
    addcreature('wagboss_robot', 'atk_missile_idle', nil, 0, 100, nil, { dist = 20 })
    addcreature('wagboss_robot', 'atk_missile', nil, 0, 100, nil, { dist = 20 })
    addcreature('wagboss_robot', 'atk_missile_pst', nil, 0, 100, nil, {
        avoid_break = function(target)
            return FindEntity(target, 20, function(ent)
                return ent.prefab == "wagboss_missile"
            end)
        end,
        dist = 20
    })

    addcreature('wagboss_robot', 'atk_signal_pre', nil, 0, 100, nil, { angle = 40 * DEGREES, dist = 20 })
    addcreature('wagboss_robot', 'atk_signal_loop', nil, 0, 100, nil, { angle = 40 * DEGREES, dist = 20 })

    addcreature('eyeofterror', 'charge_pre', nil, 0, 25,
        {
            point = "target",
            update = true,
            angle = 0 * DEGREES,
            dist = 8,
        })
    addcreature('eyeofterror', 'charge_pre', nil, 25, 33,
        {
            point = "player",
            update = false,
            angle = 90 * DEGREES,
            dist = 4,
        })
    addcreature('eyeofterror', 'charge_loop', nil, 0, 100,
        {
            point = "player",
            update = true,
            angle = 90 * DEGREES,
            dist = 4,
        }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 100
            end,
        })
    addcreature('eyeofterror', 'charge_pst', nil, 0, 100,
        {
            point = "target",
            update = false,
            angle = -45 * DEGREES,
            dist = 8,
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 100
            end,
        })
    addcreature('eyeofterror', 'chomp', calculate, 0, 25)
    copy('twinofterror1', 'eyeofterror')
    copy('twinofterror2', 'eyeofterror')

    addcreature('shadowthrall_hands', 'run_loop', nil, 0, 100,
        { update = false, angle = 80 * DEGREES, dist = 4, }, {
            breakdodgefn = function(ent)
                return EntityHelpers:GetAngle(ent, inst) > 100
            end,
        })
    addcreature('shadowthrall_hands', 'run_pre', nil, 0, 100,
        { update = false, angle = 80 * DEGREES, dist = 4, })
    addcreature('mosquito', 'atk', calculate, 0, 15)
    addcreature('bee', 'atk', calculate, 0, 15)
    copy('killerbee', 'bee')
    addcreature('grassgator', 'atk', calculate, 0, 10)
    addcreature('babybeefalo', 'atk', calculate, 0, 10)
    addcreature('spider_water', 'atk', calculate, 0, 16)
    makeNoUsed('walrus')
    makeNoUsed('monkey')
    makeNoUsed('gestalt_guard_evolved')
    addcreature('perd', 'atk', calculate, 0, 20)
    makeNoUsed('lavae')
    makeNoUsed('lavae_pet')
    makeNoUsed('bishop_nightmare')
    makeNoUsed('bishop')
    makeNoUsed('mutatedwarg')
    makeNoUsed('warg')
    makeNoUsed('rook_nightmare')
    makeNoUsed('slurper')
    addcreature('spider_common', 'atk', calculate, 0, 25)
    addcreature('spider_common', 'warrior_atk', nil, 0, 19, { angle = 120 * DEGREES, update = false })
    addcreature('spider_moon', 'atk', calculate, 0, 25, nil, { combat_offset = -3 })
    addcreature('spider_moon', 'warrior_atk', nil, 0, 19, { angle = 120 * DEGREES, update = false })
    addcreature('spider_spitter', 'atk', calculate, 0, 25, nil, { combat_offset = -2 })

    copy('spider_dropper', 'spider_moon')
    copy('spider_warrior', 'spider_moon')
    copy('spider_hider', 'spider_common')
    copy('spider_healer', 'spider_common')

    makeNoUsed('crawlinghorror')
    makeNoUsed('lunar_grazer')
    makeNoUsed('terrorbeak')
    makeNoUsed('mutateddeerclops')
    addcreature('shadowthrall_mouth', 'bite_pre', nil, 0, 100)
    addcreature('shadowthrall_mouth', 'bite_loop', nil, 0, 100)
    addcreature('shadowthrall_mouth', 'land', nil, 0, 100)
    addcreature('shadowthrall_mouth', 'leap', nil, 0, 100)
    addcreature('toadstool', 'attack_pound_pre', calculate, 0, 45, nil, { combatdist = 7.5 })
    addcreature('toadstool', 'attack_pound_loop', nil, 0, 45, nil, { combatdist = 7.5 })
    copy('toadstool_dark', 'toadstool')
    addcreature('shadow_knight', 'atk_pre', nil, 0, 100, nil,
        { combat_scale = 2 })
    addcreature('shadow_knight', 'atk', nil, 0, 3, nil,
        { combat_scale = 2 })
    addcreature('shadow_knight', 'atk_plus', nil, 0, 5, nil,
        { combat_scale = 2 })

    addcreature('beefalo', 'atk', calculate, 0, 10, nil, { calculate_offset = 0.3 })
    addcreature('lightninggoat', 'atk', calculate, 0, 12, nil, { calculate_offset = 0.2 })

    addcreature('lavae', 'atk_pre', nil, 0, 15,
        { point = "player", update = false, angle = 90 * DEGREES, })
    addcreature('lavae', 'atk', nil, 0, 6)

    addcreature('buzzard', 'atk', calculate, 0, 15)
    addcreature('mutatedbuzzard_gestalt', 'atk', calculate, 0, 15, nil, { combat_offset = -8 })
    addcreature('mutatedbuzzard_gestalt', 'atk_flame_pre', nil, 0, 100)
    addcreature('mutatedbuzzard_gestalt', 'atk_flame_loop', nil, 0, 100)

    addcreature('bernie_big', 'atk', calculate, 0, 23, { extradist = 0.25 })
    do
        copy('siving_foenix', 'buzzard')
        copy('siving_moenix', 'buzzard')

    end
    do
        addcreature('medal_naughty_krampus', 'atk_pre', nil, 0, 18)
        addcreature('medal_rage_krampus', 'atk_pre', calculate, 0, 18)
        addcreature('medal_rage_krampus', 'atk', nil, 0, 3 - safeadvance)
    end
    do
        addcreature('alpha_lightninggoat', 'atk', calculate, 0, 12)
        addcreature('alpha_lightninggoat', 'lightcharge_atk_loop', nil, 0, 100)
        addcreature('alpha_lightninggoat', 'stompy', nil, 0, 100, { dist = 6 + 2 })
        addcreature('alpha_lightninggoat', 'stompy_loop', nil, 0, 100, { dist = 6 + 2 })

        addcreature('ancient_trepidation', 'attack', calculate, 0, 12 / 12 * 16)
        addcreature('ancient_trepidation', 'attack', nil, 12 / 12 * 16, 25 / 12 * 16)

        addcreature('ancient_trepidation_arm', 'atk_pre', calculate, 0, 24 * special_mod_anim_mult, nil,
            { mod_anim = true })
        addcreature('ancient_trepidation_arm', 'atk_loop', nil, 0, 7 * special_mod_anim_mult, nil, { mod_anim = true })

        addcreature('bight', 'atk', calculate, 0, math.ceil(26 * special_mod_anim_mult), nil, { mod_anim = true })

        addcreature('creepingfear', 'atk_pre', calculate, 0, math.ceil(16 * special_mod_anim_mult), nil,
            { extradist = 1, mod_anim = true })
        addcreature('creepingfear', 'atk', nil, 0, math.ceil(4 * special_mod_anim_mult), nil,
            { extradist = 1, mod_anim = true })
        copy('eyeofterror_mini_ally', 'eyeofterror')
        addcreature('hoodedwidow', 'atk', calculate, 0, 28 * special_mod_anim_mult, nil, { mod_anim = true })
        addcreature('hoodedwidow', 'leap', nil, 0, 20 * special_mod_anim_mult,
            { update = false, angle = 0, dist = 0 }, { mod_anim = true })
        addcreature('hoodedwidow', 'shoot_pre', nil, 0, 47 * special_mod_anim_mult,
            { dist = 15 + 5 }, { mod_anim = true })
        addcreature('hoodedwidow', 'shoot_loop', nil, 0, 32,
            { dist = 15 + 5 })
        addcreature('hoodedwidow', 'shoot_pst', nil, 0, 16,
            { dist = 15 + 5 })

        addcreature('knook', 'atk_pre', calculate, 0, 36 + 7 * special_mod_anim_mult,
            {}, { mod_anim = true })
        addcreature('knook', 'atk', nil, 0, 7 * special_mod_anim_mult,
            {}, { mod_anim = true })
        addcreature('knook', 'bigjump', nil, 0, 15 * special_mod_anim_mult,
            {}, { mod_anim = true })

        copy('lavae2', 'lavae')

        addcreature('lureplague_rat', 'atk', calculate, 0, 7 * special_mod_anim_mult,
            {}, { mod_anim = true })

        addcreature('mock_dragonfly', 'taunt_pre', nil, 0, 18 + 2, {
            point = "target", update = true, angle = 0 * DEGREES })
        addcreature('mock_dragonfly', 'taunt', nil, 0, 20 + 0.6 / FRAMES, {
            point = "target", update = true, angle = 0 * DEGREES })
        copy('mothergoose', 'moose')

        addcreature('pied_rat', 'atk', calculate, 0, 18 * special_mod_anim_mult,
            { dist = 5 }, { mod_anim = true })
        copy('pigking_pigguard', 'pigman')

        addcreature('rneskeleton', 'atk_pre', calculate, 0, 10)
        addcreature('rneskeleton', 'atk', nil, 0, 4)

        addcreature('roship', 'atk', nil, 10, 100,
            {
                avoid_break = function(target)
                    return FindEntity(inst, 10, function(ent)
                        return ent.prefab == "roship_projectile"
                    end)
                end,
                angle = 120 * DEGREES,
                dist = 10,
                update = false,
            })

        addcreature('um_scorpion', 'tail', calculate, 0, 20 * special_mod_anim_mult,
            {}, { mod_anim = true })
        addcreature('um_scorpion', 'atk', calculate, 0, 19 * special_mod_anim_mult,
            {
                angle = function(ent)
                    return AttackRange(ent) >= 10 and 120 * DEGREES or 0
                end,
                update = false,
            }, { mod_anim = true })
        copy('shockworm', 'worm')
        copy('viperworm', 'worm')
        addcreature('vampirebat', 'atk', calculate, 0, 14)

        addcreature('snapdragon', 'atk_pre', calculate, 0, 15, { mod_anim = true })
        addcreature('snapdragon', 'atk', nil, 0, 3)

        addcreature('snapperturtle', 'atk', calculate, 0, 10, { mod_anim = true })
        addcreature('snapperturtlebaby', 'atk', calculate, 0, 10, { mod_anim = true })

        addcreature('snowmong', 'action', calculate, 0, 10, { mod_anim = true })
        copy('spider_trapdoor', 'spider_common')

        addcreature('stumpling', 'attack', calculate, 0, 26 * special_mod_anim_mult,
            { extradist = 2, mod_anim = true, _b = 10 })

        addcreature('swilson', 'atk', calculate, 0, 17, { mod_anim = true, _b = 13 })
        copy('lightninghound', 'hound_common')
        copy('glacialhound', 'hound_common')
        copy('sporehound', 'hound_common')
        copy('rnehound', 'hound_common')
        addcreature('magmahound', 'atk_pre', calculate, 0, 16)
        addcreature('magmahound', 'atk_magma', nil, 0, 2)
    end
    do
        addcreature('bishop', 'atk2_pre', nil, 0, 100, nil, {
            point = "player", update = true, angle = 90 * DEGREES, dist = 4
        })
        addcreature('bishop', 'atk2_loop', nil, 0, 100, nil, {
            point = "player", update = true, angle = 90 * DEGREES, dist = 4
        })
        addcreature('bishop', 'atk2_pst', nil, 0, 8, nil, {
            point = "player", update = true, angle = 90 * DEGREES, dist = 4
        })
        copy('bishop_nightmare', 'bishop')

        addcreature('cave_vent_mite', 'atk', calculate, 0, 20)
    end
    copy('spider', 'spider_common')
    return profiles
end

return M
