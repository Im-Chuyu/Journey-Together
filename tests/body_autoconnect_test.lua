package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local Auto = require("my_friend_body_autoconnect")
local function Player()
    local p = {events = {}, valid = true}
    function p:IsValid() return self.valid end
    function p:DoStaticTaskInTime(delay, fn)
        local t = {delay = delay, fn = fn}; function t:Cancel() self.cancelled = true end; return t
    end
    function p:ListenForEvent(name, fn) self.events[name] = fn end
    return p
end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("actual entry reserves RPC slots but leaves the model behavior off when disabled", function()
    local function Read(path) local file = assert(io.open(path)); local source = file:read("*a"); file:close(); return source end
    local source = Read("modmain.lua")
    local entry = assert(source:match('(local model_enabled =.-)\nlocal function IsActualCompanion'))
    local brain = assert(Read("scripts/brains/my_friendbrain.lua"):match('(if inst%._my_friend_model_enabled then\n.-)\n    local function CanWaitForPlayer'))
    for _, enabled in ipairs({false, true}) do
        local loads, installs, scores = 0, 0, 0
        local env = setmetatable({_G = {print = function() end}, inst = {_my_friend_model_enabled = enabled},
            GetModConfigData = function(key) if key == "model_enabled" then return enabled end end,
            Alive = function(fn) return fn end, Add = function() scores = scores + 1 end,
            require = function(name)
                loads = loads + 1
                if name == "my_friend_body_bridge" then return {Install = function(_, active)
                    assert(active == enabled); installs = installs + 1
                end} end
                if name == "behaviours/my_friend_body" then return function() return {} end end
                error("unexpected require: " .. name)
            end}, {__index = _G})
        local chunk = assert(loadstring(entry)); setfenv(chunk, env); chunk()
        chunk = assert(loadstring(brain)); setfenv(chunk, env); chunk()
        assert(installs == 1 and scores == (enabled and 1 or 0))
        assert(loads == (enabled and 2 or 1))
        if not enabled then
            assert(env._G.c_myfriend_ai("start", "321151") == false)
            assert(env._G.c_myfriend_body("observe").reason == "model_disabled" and loads == 1)
        end
    end
    assert(source:find('inst._my_friend_model_enabled = model_enabled', 1, true)
        < source:find('inst:SetBrain(FollowBrain)', 1, true))
end)
Test("a rejected pairing code ends the current auto-connect controller", function()
    local control = Auto.New(Player(), "123456", function() return true end)
    control.retry.fn()
    local timeout = control.timeout
    control:Result("disconnected", "pairing_code_mismatch", control.serial)
    assert(timeout.cancelled and not control.enabled and control.retry == nil and not control.connected)
    control:Result("disconnected", "network", control.serial)
    assert(control.retry == nil)
end)
Test("exactly thirty failed attempts with 5,10,...145 second waits; then no retry", function()
    local calls = 0
    local control = Auto.New(Player(), "321151", function(code) assert(code == "321151"); calls = calls + 1; return false end)
    assert(control.retry.delay == 1)
    for i = 1, 30 do
        local task = assert(control.retry); task.fn()
        assert(control.failures == i)
        if i < 30 then assert(control.retry.delay == i * 5) else assert(control.retry == nil) end
    end
    assert(calls == 30)
end)
Test("successful connection resets backoff; loss reconnects; old attempt notifications cannot count twice", function()
    local control = Auto.New(Player(), "123456", function() return true end)
    control.retry.fn(); local stale = control.serial
    control:Result("failed", "network", stale); assert(control.retry.delay == 5)
    control.retry.fn(); local current = control.serial
    control:Result("failed", "late", stale); assert(control.failures == 1 and control.connecting)
    control:Result("connected", nil, current); assert(control.failures == 0 and control.retry == nil and control.timeout == nil)
    control:Result("disconnected", "network", current); assert(control.retry.delay == 0)
    control.retry.fn(); control.timeout.fn(); assert(control.failures == 1 and control.retry.delay == 5)
end)
Test("manual stop/removal clean tasks and a new world starts with a fresh retry budget", function()
    local player = Player(); local control = Auto.New(player, "321151", function() return true end)
    local pending = control.retry; control:Stop(); assert(pending.cancelled and control.retry == nil)
    control:Result("disconnected"); assert(control.retry == nil)
    local next_world = Auto.New(Player(), "321151", function() return true end)
    next_world.retry.fn(); local timeout = next_world.timeout
    next_world.player.events.onremove(); assert(timeout.cancelled and not next_world.enabled)
end)
Test("all four locales expose disabled-by-default model mode and customizable six-digit defaults", function()
    for _, locale in ipairs({"zh", "zht", "en", "ru"}) do
        local env = {locale = locale}
        local chunk = assert(loadfile("modinfo.lua")); setfenv(chunk, env); chunk()
        local found = {}; for _, option in ipairs(env.configuration_options) do found[option.name] = option end
        assert(found.model_enabled.default == false)
        local code = ""; for i = 1, 6 do
            local digit = assert(found["model_pair_digit_" .. i]); assert(#digit.options == 10)
            code = code .. digit.default
        end
        assert(code == "321151")
    end
end)
print(passed .. " auto-connect tests passed")
