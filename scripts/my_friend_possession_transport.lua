-- A borrowed body can leave its AI behind on another shard. Only those
-- split exchanges need transport; ordinary returns never leave the shard.
local M = {}
local CHUNK = 6000
local MAX_PARTS = 4096

local function SendPart(shard, ...)
    SendModRPCToShard(GetShardModRPC("MyFriends", "PossessionReturn"), {shard}, ...)
end

function M.Send(shard, kind, userid, token, payload)
    if not Shard_IsWorldAvailable(shard) then return end
    if payload == nil then
        SendPart(shard, kind, userid, token)
        return
    end
    local world = TheWorld
    world._my_friend_return_sends = world._my_friend_return_sends or {}
    local sends = world._my_friend_return_sends
    local key = kind .. ":" .. token
    if sends[key] then return end
    local text = DataDumper(payload, nil, true)
    local total = math.ceil(#text / CHUNK)
    if total > MAX_PARTS then
        print("[MyFriends] Body exchange record exceeds shard transfer limit; retaining " .. token)
        return
    end
    sends[key] = true
    local index = 1
    local function Pump()
        if Shard_IsWorldAvailable(shard) then
            for i = index, math.min(index + 3, total) do
                SendPart(shard, kind, userid, token, i, total, text:sub((i - 1) * CHUNK + 1, i * CHUNK))
            end
            index = index + 4
            if index <= total then world:DoStaticTaskInTime(.1, Pump) return end
        end
        sends[key] = nil
    end
    Pump()
end

function M.Receive(source, kind, userid, token, index, total, part)
    local world = TheWorld
    source = tostring(source)
    if world == nil or not world.ismastersim or world._my_friend_loading
        or type(userid) ~= "string" or #userid == 0 or #userid > 128
        or type(token) ~= "string" or #token == 0 or #token > 512 or source == tostring(TheShard:GetShardId())
        or not Shard_IsWorldAvailable(source) then return end
    local possess = require("my_friend_possess")
    if not possess.ExpectsReturn(source, kind, userid, token) then return end
    if kind == "claimed" or kind == "done" or kind == "located" then
        possess.OnReturnMessage(source, kind, userid, token)
        return
    end
    if type(index) ~= "number" or type(total) ~= "number" or index % 1 ~= 0 or total % 1 ~= 0
        or index < 1 or index > total or total > MAX_PARTS or type(part) ~= "string" or #part > CHUNK then return end
    world._my_friend_return_parts = world._my_friend_return_parts or {}
    local buffers = world._my_friend_return_parts
    local key = source .. ":" .. kind .. ":" .. token
    local b = buffers[key]
    if b == nil or b.total ~= total then
        if b ~= nil then b.cleanup:Cancel() end
        b = {parts = {}, count = 0, total = total}
        buffers[key] = b
        b.cleanup = world:DoStaticTaskInTime(180, function() if buffers[key] == b then buffers[key] = nil end end)
    end
    if b.parts[index] == nil then b.count = b.count + 1 end
    b.parts[index] = part
    if b.count == total then
        buffers[key] = nil
        b.cleanup:Cancel()
        local ok, record = RunInSandboxSafe(table.concat(b.parts))
        if ok and type(record) == "table" then possess.OnReturnMessage(source, kind, userid, token, record) end
    end
end

return M
