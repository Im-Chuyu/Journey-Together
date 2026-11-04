-- Exercise the actual wheel/server lookup functions without loading UI or a world.
local function Read(path)
    local f=assert(io.open(path,"rb"));local s=f:read("*a"):gsub("\r","");f:close();return s
end
local source=Read("scripts/widgets/my_friend_command_wheel.lua")
local start=assert(source:find("function MyFriendCommandWheel:FindFriend(ai_only)",1,true))
local finish=assert(source:find("\nfunction MyFriendCommandWheel:ShowFor",start,true))
local Wheel=assert(loadstring("local MyFriendCommandWheel={}\n"..source:sub(start,finish-1).."\nreturn MyFriendCommandWheel"))()
local function Entity(x,kind)
    local e={isplayer=true,prefab=kind or "wendy",valid=true,companion=true}
    function e:IsValid()return self.valid end
    function e:HasTag(tag)return tag=="my_friend" and self.companion or tag=="my_friend_possessing" and self.possessing end
    function e:Remove()self.removed=true end
    e.Transform={GetWorldPosition=function()return x,0,0 end}
    return e
end
local function Setup()
    local owner=Entity(0,"wilson");owner.companion=false
    local wheel={owner=owner}
    TheInput={GetWorldEntityUnderMouse=function()return nil end}
    Ents={}
    return wheel,owner
end
local passed=0
local function Test(name,fn)fn();passed=passed+1;print("PASS "..name)end
Test("R lookup skips foreign values, broken methods and invalid coordinates",function()
    local wheel,owner=Setup();local valid=Entity(4)
    Ents={false,7,"bad",function()end,io.stdout,{}, {IsValid=true},
        setmetatable({},{__index=function()error("foreign table must not be indexed")end}),
        {isplayer=true,IsValid=function()error("bad entity")end,HasTag=function()return true end},
        Entity(0/0),Entity(math.huge),valid}
    local dead=Entity(1);dead.valid=false;Ents[#Ents+1]=dead
    local bad=Entity(2);bad.Transform=23;Ents[#Ents+1]=bad
    local notplayer={IsValid=function()error("must not query every world's IsValid")end};Ents[#Ents+1]=notplayer
    owner.HUD={controls={my_friend_panel={friend=99}}}
    TheInput.GetWorldEntityUnderMouse=function()return "invalid mouse target"end
    assert(Wheel.FindFriend(wheel)==valid)
end)
Test("valid cached and mouse preferences, nearest selection and Abigail exclusion stay unchanged",function()
    local wheel,owner=Setup();local near,far=Entity(3),Entity(12)
    Ents={Entity(1,"abigail"),far,near}
    assert(Wheel.FindFriend(wheel)==near)
    TheInput.GetWorldEntityUnderMouse=function()return far end
    assert(Wheel.FindFriend(wheel)==far)
    owner.HUD={controls={my_friend_panel={friend=near}}}
    assert(Wheel.FindFriend(wheel)==near)
end)
Test("possession release and empty-world lookup retain their original behaviour",function()
    local wheel,owner=Setup();owner.possessing=true
    assert(Wheel.FindFriend(wheel)==owner and Wheel.FindFriend(wheel,true)==nil)
    owner.possessing=false;Ents=nil;assert(Wheel.FindFriend(wheel)==nil)
end)
Test("server lookup ignores malformed values and still configures one companion and removes duplicates",function()
    local mod=Read("modmain.lua")
    local a=assert(mod:find("local function FindFriend()",1,true))
    local b=assert(mod:find("\n-- The possession helper",a,true))
    local configured={};local first,second,parked=Entity(1),Entity(2),Entity(3);parked._my_friend_possess_parked=true
    local globals={rawget=rawget,pcall=pcall,Ents={false,12,"foreign",{},
        setmetatable({},{__index=function()error("foreign table must not be indexed")end}),
        {prefab="wendy",IsValid=true},
        {prefab="wendy",IsValid=function()error("broken actor")end,HasTag=function()return true end,Remove=function()end},first,parked,second}}
    -- modmain.lua sees these helpers through GLOBAL, not in the mod environment.
    local chunk=assert(loadstring("local _G,Characters,ConfigureFriend=...\n"..mod:sub(a,b-1).."\nreturn FindFriend"))
    setfenv(chunk,{pairs=pairs,type=type})
    local find=chunk(
        globals,{IsCharacter=function(name)return name=="wendy"end},function(e)configured[#configured+1]=e;return e end)
    local entities=globals.Ents
    globals.Ents={{prefab="archive_security_desk"}}
    assert(find()==nil)
    globals.Ents=entities
    local result=find()
    assert(#configured==1 and (result==first or result==second) and first.removed~=second.removed and not parked.removed)
    globals.Ents=nil;assert(find()==nil)
end)
Test("panel inventory RPCs reject inactive bodies and malformed slots", function()
    package.path = "./scripts/?.lua;" .. package.path
    local mod = Read("modmain.lua")
    local function Section(first, last)
        local a = assert(mod:find(first, 1, true))
        local b = assert(mod:find(last, a, true))
        return mod:sub(a, b - 1)
    end
    local owner, active, stale = Entity(0), Entity(2), Entity(2)
    owner.companion = false
    AllPlayers = {owner}
    active.components = {inventory = {}, my_friend_affinity = {}}
    stale.components = active.components
    local globals = {TheWorld = {ismastersim = true, _my_friend = active}}
    local handlers, handled = {}, 0
    local chunk = assert(loadstring([[
        local _G, AddModRPCHandler, IsActualCompanion, GetFriendStorage, HandleFriendStorageSlot = ...
    ]] .. Section("local function CanManage(", 'AddModRPCHandler("MyFriends", "Rename"')
        .. Section('AddModRPCHandler("MyFriends", "ClickSlot"', 'AddModRPCHandler("MyFriends", "QuickMoveFriendSlot"')))
    chunk(globals, function(_, name, handler) handlers[name] = handler end,
        function(friend) return friend:IsValid() and friend:HasTag("my_friend") end,
        function() return {}, 15 end,
        function(_, _, _, slot) assert(slot == 1); handled = handled + 1 end)
    for _, handler in pairs(handlers) do
        handler(owner, active, 0/0)
        handler(owner, active, math.huge)
        handler(owner, active, 1.5)
        handler(owner, stale, 1)
        handler(owner, 42, 1)
        handler(owner, active, 1)
    end
    assert(handled == 2)
end)
print(passed.." friend lookup tests passed")
