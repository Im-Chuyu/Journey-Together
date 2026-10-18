package.path = "scripts/?.lua;" .. package.path
local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k,v in pairs(value) do out[k] = clone(v) end; return out
end
local tokens = {}
package.loaded.json = {encode = function(value) tokens[#tokens + 1] = clone(value); return tostring(#tokens) end,
    decode = function(value) assert(tokens[tonumber(value)]); return clone(tokens[tonumber(value)]) end}
if arg[1] ~= nil then dofile(arg[1]); package.loaded.json = _G.json end
local json, History = require("json"), require("my_friend_games_history")
local disk, work, reads, writes = {}, {}, 0, 0
local fail
local function read(key, cb)
    reads = reads + 1
    work[#work + 1] = function() cb(disk[key] ~= nil, disk[key]) end
end
local function write(key, value, cb)
    writes = writes + 1
    work[#work + 1] = function()
        if fail then fail = nil; cb(false) else disk[key] = value; cb(true) end
    end
end
local function flush()
    while #work > 0 do local fn = table.remove(work,1); fn() end
end
local archive = History.New(read, write, "test_")
assert(reads == 0 and writes == 0, "no archive IO before an event")
for i = 1, 65 do
    archive:Append({game = i % 2 == 0 and "go" or "gomoku", names = {"甲", "乙"}, winner = i % 2 + 1, serial = i})
end
assert(#archive.queue == 65 and reads == 1 and writes == 0, "concurrent finishes share one initial read")
flush()
assert(archive.total == 65 and #archive.tail == 5 and #archive.queue == 0)
assert(#json.decode(disk.test_1) == 20 and #json.decode(disk.test_2) == 20 and #json.decode(disk.test_3) == 20)
assert(json.decode(disk.test_head).total == 65)
local result
archive:Page(1,function(data) result = data end)
assert(#result.rows == 5 and result.rows[1].serial == 65 and result.pages == 4)
archive:Page(2,function(data) result = data end); flush()
assert(result.rows[1].serial == 60 and result.rows[20].serial == 41)
archive:Page(100,function(data) result = data end); flush()
assert(result.page == 4 and result.rows[20].serial == 1)
-- Recreate the service as after restarting, reading only its tiny head.
local reloaded = History.New(read, write, "test_")
local before = reads
reloaded:Page(1,function(data) result = data end); flush()
assert(reads == before + 1 and reloaded.total == 65 and #reloaded.tail == 5 and result.rows[1].serial == 65)
-- A failed write never discards queued results or advances the committed head.
fail = true; reloaded:Append({game="go",names={"A","B"},draw=true,serial=66}); flush()
assert(reloaded.total == 65 and #reloaded.queue == 1)
reloaded:Page(1,function(data) result = data end); flush()
assert(reloaded.total == 66 and #reloaded.queue == 0 and json.decode(disk.test_head).total == 66)
-- Failure sealing a full page also preserves the head and tail for retry.
local full = History.New(read, write, "full_")
for i = 1,20 do full:Append({serial=i}) end; flush()
fail=true; full:Append({serial=21}); flush()
assert(full.total==20 and #full.tail==20 and #full.queue==1)
full:Page(1,function() end); flush()
assert(full.total==21 and json.decode(disk.full_1)[20].serial==20)
-- A corrupt index must not be replaced with an empty archive.
disk.bad_head = "not json"
local bad = History.New(read,write,"bad_")
bad:Append({serial=1}); flush()
assert(not bad.loaded and bad.total==0 and #bad.queue==1 and disk.bad_head=="not json")
disk.blank_head=""
local blank=History.New(read,write,"blank_")
blank:Append({serial=1}); flush()
assert(not blank.loaded and #blank.queue==1 and disk.blank_head=="", "a truncated empty head must not be overwritten")
local read_error=History.New(function(_,cb) cb(false) end,write,"existing_",function(_,cb) cb(true) end)
local oldwrites=writes
read_error:Append({serial=1})
assert(not read_error.loaded and read_error.failed and #read_error.queue==1 and writes==oldwrites,
    "an unreadable existing head must never be replaced with an empty archive")
local empty = History.New(read,write,"other_")
empty:Page(1,function(data) result=data end); flush()
assert(result.total==0 and #result.rows==0)
-- World/session/shard scoping and on-demand, idempotent creation.
TheSim={GetPersistentString=function(_,key,cb) read(key,cb) end,SetPersistentString=function(_,key,value,_,cb) write(key,value,cb) end}
TheShard={GetShardId=function() return "Caves" end}
local world={meta={session_identifier="sessionA"}}
local scoped=History.ForWorld(world)
assert(scoped==History.ForWorld(world) and scoped.prefix=="my_friend_games_sessionA_Caves_")
assert(next(work)==nil and scoped.loaded==nil)
print("PASS: all-result paginated archive, restart, async serialization, failed-write retries, corruption guard, bounded resident pages and world/shard isolation")
