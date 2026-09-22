-- Which player characters may act as the companion, and the mapping between a
-- character prefab ("wilson") and the name its save record is written under
-- ("my_friend_wilson"). See DEVELOPER.md section 1.1 for why the save name
-- differs from the runtime prefab.
local M = {}

-- The character a brand new companion is created as.
M.DEFAULT = "wendy"
M.SAVE_PREFIX = "my_friend_"

-- Vanilla characters that have to be bought. Kept as a literal fallback
-- because GetSkinData is not guaranteed to be reachable on every host; the
-- live is_restricted flag is preferred whenever it can be read.
local PAID = {
    wanda = true,
    wormwood = true,
    wortox = true,
    wurt = true,
}

-- Paid characters are offered to nobody, so the server never has to reason
-- about another player's entitlements.
--
-- The static table wins: skin data is not always populated when the prefab
-- file is loaded, and a missing is_restricted flag would otherwise read as
-- "free". The live check can only ever add to the list, never remove from it.
function M.IsPaid(name)
    if PAID[name] then return true end
    if IsRestrictedCharacter ~= nil then
        local ok, restricted = pcall(IsRestrictedCharacter, name)
        if ok and restricted == true then return true end
    end
    return false
end

-- wonkey is reached only through the in-game seamless swap and cannot be
-- spawned directly; SEAMLESSSWAP_CHARACTERLIST holds that set.
local function IsExcluded(name)
    for _, excluded in ipairs(SEAMLESSSWAP_CHARACTERLIST or {}) do
        if excluded == name then return true end
    end
    return false
end

-- Vanilla characters first, then whatever other mods registered.
--
-- Cached, because FindFriend and the save hook ask about every entity in the
-- world. The cache is keyed on the size of MODCHARACTERLIST so it rebuilds
-- itself if a character mod that loads after this one registers late.
local cache, cache_mods, cache_set = nil, nil, nil

local function Rebuild()
    local mods = MODCHARACTERLIST or {}
    if cache ~= nil and cache_mods == #mods then return end
    cache, cache_set, cache_mods = {}, {}, #mods
    for _, source in ipairs({ DST_CHARACTERLIST or {}, mods }) do
        for _, name in ipairs(source) do
            if type(name) == "string" and not cache_set[name] and not IsExcluded(name) then
                cache_set[name] = true
                cache[#cache + 1] = name
            end
        end
    end
end

function M.List()
    Rebuild()
    return cache
end

function M.IsCharacter(prefab)
    if type(prefab) ~= "string" then return false end
    Rebuild()
    return cache_set[prefab] == true
end

function M.IsModCharacter(prefab)
    for _, name in ipairs(MODCHARACTERLIST or {}) do
        if name == prefab then return true end
    end
    return false
end

function M.SavePrefab(prefab)
    return M.SAVE_PREFIX .. tostring(prefab)
end

function M.FromSavePrefab(name)
    if type(name) ~= "string" then return end
    local character = name:match("^" .. M.SAVE_PREFIX .. "(.+)$")
    return character ~= nil and M.IsCharacter(character) and character or nil
end

-- A save record can only be rebuilt when the matching wrapper prefab exists.
-- Note this deliberately covers paid characters too: a wrapper is registered
-- for every character so that no save can ever become unloadable, even if a
-- companion somehow ended up as one of them.
function M.IsSupported(prefab)
    return M.IsCharacter(prefab)
        and Prefabs ~= nil and Prefabs[M.SavePrefab(prefab)] ~= nil
end

-- What the panel may offer and the server will accept. Paid characters are
-- filtered here rather than in List(), so existing entities keep working
-- while nobody can pick one.
function M.IsSelectable(prefab)
    return M.IsSupported(prefab) and not M.IsPaid(prefab)
        and Prefabs[prefab] ~= nil
end

function M.Selectable()
    local list = {}
    for _, name in ipairs(M.List()) do
        if M.IsSelectable(name) then list[#list + 1] = name end
    end
    return list
end

function M.CanBecome(prefab)
    return M.IsSelectable(prefab)
end

function M.Of(inst)
    return inst ~= nil and inst.prefab or nil
end

return M
