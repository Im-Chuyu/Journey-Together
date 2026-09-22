-- Routes every companion line through the vanilla "chatter" network path so
-- nearby players see it both as a speech bubble and in their chat window,
-- exactly like the Hermit Crab. Only a short key travels over the wire; the
-- text itself lives in the selected scripts/languages/<code>/dialogue_lines.lua
-- file on every machine.
local Language = require("my_friend_strings")
local LanguageFiles = require("my_friend_language")

local M = {}

M.TABLE = "MY_FRIEND_SPEECH"
M.MAX_DURATION = 7
local SEPARATOR = "\1"
local ARGUMENT_TOKEN = "{1}"
-- Per character overrides are stored under "<character>/<key>"; a bare
-- "<key>" is the shared default. See M.Key.
local CHARACTER_SEPARATOR = "/"

local function Priority()
    return CHATPRIORITIES ~= nil and CHATPRIORITIES.LOW or 1
end

local function Register(strings, prefix, source)
    for key, group in pairs(type(source.lines) == "table" and source.lines or {}) do
        local resolved = {}
        for _, line in ipairs(group) do
            if type(line) == "table" and type(line[1]) == "string" then
                resolved[#resolved + 1] = line[2] ~= nil
                    and Language.Text(line[1], line[2]) or line[1]
            end
        end
        if #resolved > 0 then strings[prefix .. key] = resolved end
    end
    for key, line in pairs(type(source.replies) == "table" and source.replies or {}) do
        if type(line) == "table" then
            local resolved = {}
            for _, entry in ipairs(line) do
                if type(entry) == "string" then
                    resolved[#resolved + 1] = entry
                elseif type(entry) == "table" and type(entry[1]) == "string" then
                    resolved[#resolved + 1] = entry[2] ~= nil
                        and Language.Text(entry[1], entry[2]) or entry[1]
                end
            end
            if #resolved > 0 then strings[prefix .. key] = resolved end
        end
    end
end

-- Resolved once per language so the networked id stays a plain array index.
--
-- All shared and character-specific keys are kept in the selected language
-- file, so contributors only need to submit one dialogue file per language.
function M.BuildStrings()
    local strings = {}
    local lines = LanguageFiles.DialogueLines(Language.language)
    Register(strings, "", lines)
    STRINGS[M.TABLE] = strings
    return strings
end

local function Group(key)
    local strings = STRINGS[M.TABLE]
    return strings ~= nil and strings[key] or nil
end

-- The key actually spoken: the speaker's own line when it has one, otherwise
-- the shared default. This resolved key is what travels over the wire, so
-- clients need no knowledge of who is speaking.
function M.Key(inst, key)
    local character = inst ~= nil and inst.prefab or nil
    if character ~= nil and Group(character .. CHARACTER_SEPARATOR .. key) ~= nil then
        return character .. CHARACTER_SEPARATOR .. key
    end
    return key
end

function M.Count(key)
    local group = Group(key)
    return group ~= nil and #group or 0
end

function M.CountFor(inst, key)
    return M.Count(M.Key(inst, key))
end

function M.Text(key, index, argument)
    local group = Group(key)
    local line = group ~= nil and group[index or 1] or nil
    if line == nil then return end
    if argument ~= nil and argument ~= "" then
        if line:find(ARGUMENT_TOKEN, 1, true) ~= nil then
            line = line:gsub(ARGUMENT_TOKEN, function() return argument end)
        else
            line = argument .. Language.Text("，", ", ") .. line
        end
    end
    return line
end

-- Vanilla behaviour, for anything that chatters through a table path.
local function ResolveVanilla(strid, strtbl)
    local entries = strtbl:value():split(".")
    local data = STRINGS
    for index, entry in ipairs(entries) do
        data = data[entry]
        if data == nil then
            return
        elseif index == #entries then
            local id = strid:value()
            return (id == 0 and data) or data[id]
        end
    end
end

-- Client side resolver for talker.chatter. Receives the raw net variables.
function M.Resolve(inst, strid, strtbl)
    local raw = strtbl:value()
    if type(raw) ~= "string" or raw == "" then return end
    local key, argument = raw, nil
    local split = raw:find(SEPARATOR, 1, true)
    if split ~= nil then
        key, argument = raw:sub(1, split - 1), raw:sub(split + 1)
    end
    return M.Text(key, math.max(1, strid:value()), argument)
        or ResolveVanilla(strid, strtbl)
end

-- Called for every character on both the server and the clients so the chatter
-- network variables are created in the same order on each machine.
function M.Configure(inst)
    local talker = inst.components ~= nil and inst.components.talker or nil
    if talker == nil or inst._my_friend_speech_configured then return end
    inst._my_friend_speech_configured = true
    talker.resolvechatterfn = M.Resolve
    talker:MakeChatter()
    require("my_friend_voice").Configure(inst)
end

-- Speaks one line. Returns false when the key or index does not exist so the
-- caller can fall back; a missing chatter channel degrades to a local bubble.
function M.Say(inst, key, index, duration, argument, quiet)
    if inst == nil or not inst:IsValid() then return false end
    local talker = inst.components ~= nil and inst.components.talker or nil
    if talker == nil then return false end
    index = math.max(1, math.min(255, math.floor(index or 1)))
    key = M.Key(inst, key)
    local text = M.Text(key, index, argument)
    if text == nil then return false end
    duration = math.max(1, math.min(M.MAX_DURATION, math.floor(duration or 3)))
    if talker.chatter ~= nil and TheWorld ~= nil and TheWorld.ismastersim then
        local payload = (argument ~= nil and argument ~= "")
            and (key .. SEPARATOR .. argument) or key
        talker:Chatter(payload, index, duration, true, Priority())
        return true
    end
    talker:Say(text, duration, quiet == true, false, false, nil, nil, nil, nil,
        quiet and { my_friend_dialogue = true } or nil)
    return true
end

-- Convenience wrapper for the fixed one-line replies.
function M.Reply(inst, key, argument)
    return M.Say(inst, key, 1, M.MAX_DURATION, argument)
end

function M.Random(inst, key, duration, argument, quiet)
    local count = M.CountFor(inst, key)
    if count == 0 then return false end
    return M.Say(inst, key, math.random(count), duration, argument, quiet)
end

return M
