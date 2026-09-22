-- One wrapper prefab per playable character. The companion entity is a real
-- vanilla character at runtime, but the world save groups entities by prefab
-- name, so it is written out under "my_friend_<character>". Without this mod
-- those prefabs do not exist, the loader skips the record, and the companion
-- disappears with the mod instead of being left behind as a lifeless player.
--
-- "my_friend_wendy" must keep its name: worlds saved by earlier versions of
-- this mod already reference it.
local Characters = require("my_friend_characters")

local function MakeFn(character)
    return function()
        local base = Prefabs ~= nil and Prefabs[character] or nil
        if base == nil or base.fn == nil then
            print("[MyFriends] Cannot restore the companion: the "
                .. tostring(character) .. " prefab is missing")
            return
        end
        local inst = base.fn(TheSim)
        if inst ~= nil then
            -- SpawnPrefabFromSim prefers inst.prefab over the spawned name, so
            -- every other system (skins, stategraph, prefab post inits,
            -- remains, dialogue) keeps seeing an ordinary character.
            inst.prefab = character
        end
        return inst
    end
end

-- No assets and no deps on purpose. Listing the character as a dependency
-- made the mod's own prefab pull in the animation data for every playable
-- character the moment the mod registered, costing seconds of load time in
-- both the front end and the back end pass. It was pure duplication:
-- gamelogic loads GetActiveCharacterList() before the world spawns, so every
-- character is already in memory by the time a companion can exist.
local prefabs = {}
for _, character in ipairs(Characters.List()) do
    prefabs[#prefabs + 1] = Prefab(Characters.SavePrefab(character),
        MakeFn(character))
end

return unpack(prefabs)
