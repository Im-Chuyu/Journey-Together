-- Exercise real native chatter/history functions, with only UI/net boundaries stubbed.
-- lua tests/speech_chat_test.lua [matching-current-game native scripts directory]
package.path = "./scripts/?.lua;" .. package.path
local function Read(path)
    local file = assert(io.open(path, "rb")); local source = file:read("*a"):gsub("\r", ""); file:close(); return source
end
local function Native(path)
    if arg[1] ~= nil then return Read(arg[1] .. "/" .. path) end
    -- The user's partially unpacked yuanma is older and lacks silent chatter.
    -- Read the current game package directly; no fixtures or Temp files needed.
    local pipe = assert(io.popen([[python -B -c "import sys,zipfile; sys.stdout.buffer.write(zipfile.ZipFile('../../data/databundles/scripts.zip').read('scripts/]]
        .. path .. [['))"]], "r"))
    local source = pipe:read("*a"):gsub("\r", ""); pipe:close()
    assert(#source > 0, "current native scripts unavailable")
    return source
end
local talker_source = Native("components/talker.lua")
local history_source = Native("chathistory.lua")
assert(history_source:find("priority, silent)", 1, true), "native source predates silent chatter; use the current game scripts.zip")
local function Method(source, name)
    local start = assert(source:find("function ChatHistoryManager:" .. name .. "(", 1, true))
    local stop = source:find("\nfunction ", start + 1) or #source + 1
    return source:sub(start, stop - 1)
end
local start = assert(talker_source:find("local function ResolveChatterString", 1, true))
local stop = assert(talker_source:find("function Talker:MakeChatter()", start, true))
local NativeChatter = assert(loadstring(talker_source:sub(start, stop - 1) .. "\nreturn OnChatterDirty"))()
ChatHistoryManager = {}
assert(loadstring(Method(history_source, "OnChatterMessage")))()
-- AddToHistory is followed by a local helper; retaining it is harmless.
assert(loadstring(Method(history_source, "AddToHistory")))()
local Speech = require("my_friend_speech")
STRINGS, WHITE, DEFAULT_PLAYER_COLOUR = {}, {1, 1, 1, 1}, {1, 1, 1}
CHATPRIORITIES, ChatTypes = {LOW = 1}, {ChatterMessage = "chatter"}
PLAYER_CAMERA_SEE_DISTANCE_SQ = 900
function shallowcopy(value) local out = {}; for k, v in pairs(value) do out[k] = v end; return out end
Speech.BuildStrings()
local function Net(value) return {value = function() return value end} end
local function Setup(master)
    local notices, bubbles = {}, {}
    TheWorld = {ismastersim = master == true}
    ThePlayer = {HUD = {}, distance = 1, HasTag = function() return false end}
    function ThePlayer:GetDistanceSqToInst() return self.distance^2 end
    TheFocalPoint = {distance = 1}
    function TheFocalPoint:GetDistanceSqToInst() return self.distance^2 end
    Profile = {enabled = true, level = 1}
    function Profile:GetNPCChatEnabled() return self.enabled end
    function Profile:GetNPCChatLevel() return self.level end
    ChatHistory = setmetatable({history = {}, history_start = 0, MAX_CHAT_HISTORY = 100,
        NPC_CHATTER_MAX_CHAT_NO_DUPES = 10, listeners = {[function(message) notices[#notices + 1] = message end] = true}},
        {__index = ChatHistoryManager})
    function ChatHistory:GenerateChatMessage(kind, userid, netid, name, message)
        return {type = kind, sender_name = name, message = message}
    end
    function ChatHistory:GetChatMessageAtIndex(index)
        return self.history[(self.history_start - index) % self.MAX_CHAT_HISTORY + 1]
    end
    local inst = {components = {}, companion = true}
    function inst:HasTag(tag) return tag == "my_friend" and self.companion end
    function inst:GetDisplayName() return "温蒂" end
    local talker = {inst = inst, resolvechatterfn = Speech.Resolve}
    function talker:Say(text) bubbles[#bubbles + 1] = text end
    function talker:ShutUp() error("unexpected unresolved chatter") end
    inst.components.talker = talker
    local function Speak(key, text)
        talker.chatter = {strtbl = Net(key .. "\1" .. text), strid = Net(1), strtime = Net(7),
            forcetext = Net(true), echotochatpriority = Net(1)}
        NativeChatter(inst)
    end
    return inst, notices, bubbles, Speak
end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("model replies notify once at close range on both host and remote client", function()
    for _, master in ipairs({true, false}) do
        local inst, notices, bubbles, speak = Setup(master)
        speak("ai_dynamic", "我带着草和木头。")
        assert(#bubbles == 1 and #notices == 1 and ChatHistory.history_start == 1)
        assert(notices[1].message == bubbles[1] and notices[1].sender_name == "温蒂")
        local wrapper = ChatHistory.OnChatterMessage
        speak("wendy/ai_dynamic", "我这就过来。")
        assert(#notices == 2 and ChatHistory.OnChatterMessage == wrapper)
        assert(ChatHistory.history_start == 2) -- no second manual history insertion
    end
end)
Test("ordinary companion lines and other NPCs retain native close-range silence", function()
    local inst, notices, bubbles, speak = Setup(false)
    speak("ai_dynamic", "第一句。") -- install the wrapper
    speak("follow_ok", "玩家")
    assert(#notices == 1 and #bubbles == 2 and ChatHistory.history_start == 2,
        "ordinary line counts: " .. #notices .. "," .. #bubbles .. "," .. ChatHistory.history_start)
    inst.companion = false
    speak("ai_dynamic", "别的角色。")
    assert(#notices == 1 and #bubbles == 3 and ChatHistory.history_start == 3)
end)
Test("native range, chat preferences and duplicate suppression remain authoritative", function()
    local inst, notices, bubbles, speak = Setup(false)
    ThePlayer.distance = 31
    speak("ai_dynamic", "范围之外。")
    assert(#bubbles == 1 and #notices == 0 and ChatHistory.history_start == 0)
    ThePlayer.distance, Profile.enabled = 1, false
    speak("ai_dynamic", "已关闭NPC聊天。")
    assert(#notices == 0 and ChatHistory.history_start == 0)
    Profile.enabled, Profile.level = true, 2
    speak("ai_dynamic", "优先级设置不符。")
    assert(#notices == 0 and ChatHistory.history_start == 0)
    Profile.level = 1
    speak("ai_dynamic", "重复内容。")
    speak("ai_dynamic", "重复内容。")
    assert(#notices == 1 and ChatHistory.history_start == 1)
end)
Test("a dedicated server without local HUD/history does not add chat or fail", function()
    local inst, notices, bubbles, speak = Setup(true)
    ThePlayer, ChatHistory = nil, nil
    speak("ai_dynamic", "专服没有本地聊天窗口。")
    assert(#bubbles == 1 and #notices == 0 and ChatHistory == nil)
end)
print(passed .. " speech chat tests passed")
