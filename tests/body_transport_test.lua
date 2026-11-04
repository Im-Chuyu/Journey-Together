-- Reuse the body test's engine fixture, stopping before its test cases.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local json = require("json")
local f = assert(io.open("tests/body_api_test.lua", "rb")); local text = f:read("*a"):gsub("\r\n", "\n"); f:close()
local prefix = assert(text:match("^(.-)local passed = 0"))
local fixture = assert(loadstring(prefix .. "\nreturn {setup=Setup,perform=Perform,entity=Entity,advance=function(n) now=now+n end}"))()
local API = require("my_friend_body_api")
local Bridge = require("my_friend_body_bridge")
local function Setup()
    local inst, player = fixture.setup()
    API.Close(inst, "fixture")
    local requests = {}
    TheSim.QueryServer = function(_, url, callback, method, payload)
        requests[#requests + 1] = {url = url, callback = callback, method = method, data = json.decode(payload)}
    end
    return inst, player, requests
end
local function Reply(request, data) request.callback(json.encode(data), true, 200) end
local function Connect(inst, p, requests)
    assert(Bridge.Connect(inst, p, "481529"))
    assert(#requests == 1 and requests[1].method == "POST" and requests[1].data.code == "481529")
    Reply(requests[1], {token = "test-token"})
    assert(#requests == 2 and requests[2].data.token == "test-token")
    return inst._my_friend_body
end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("physical model plan stays leased between steps and a released or stale lease cannot seize control", function()
    local inst, player, requests = Setup(); local state = Connect(inst, player, requests)
    Reply(requests[2], {commands = {{request_id = "lease-move", skill = "move_to", arguments = {position = {x = 4, z = 0}},
        revision = 0, source = "direct", plan_id = "plan-1"}}, plan = {id = "plan-1", revision = 0, active = true}})
    fixture.perform(inst)
    assert(state.active == nil and API.PlanActive(inst) and not API.AllowLocal(inst, "backpack_recovery", {}))
    state.poll.fn(); Reply(requests[#requests], {plan = {id = "plan-1", revision = 0, active = false}})
    assert(not API.PlanActive(inst) and API.AllowLocal(inst, "recipe_cooking", {}))
    API.ManualTakeover(inst)
    state.poll.fn(); Reply(requests[#requests], {plan = {id = "plan-1", revision = 0, active = true}})
    assert(not API.PlanActive(inst))
    API.Close(inst, "done")
end)
Test("import/configuration perform no network call; pairing validates its code", function()
    local inst, player, requests = Setup()
    assert(#requests == 0 and not Bridge.Connect(inst, player, "bad") and #requests == 0)
    local state = Connect(inst, player, requests)
    assert(requests[2].data.snapshot.prefab == "wendy")
    API.Close(inst, "done"); assert(inst._my_friend_body == nil and state.token == "test-token")
end)
Test("actual exchange dispatches move, sends actual receipt and acknowledges it", function()
    local inst, player, requests = Setup(); local state = Connect(inst, player, requests)
    Reply(requests[2], {commands = {{request_id = "move-1", skill = "move_to", arguments = {position = {x = 8, z = 2}, gait = "run"}}}})
    assert(state.active ~= nil)
    fixture.perform(inst)
    state.poll.fn()
    local exchange = requests[#requests]
    local completed
    for _, e in ipairs(exchange.data.events) do if e.request_id == "move-1" and e.status == "completed" then completed = e end end
    assert(completed and completed.result.position.x == 8)
    local ack = {}; for _, e in ipairs(exchange.data.events) do ack[#ack + 1] = e.event_id end
    Reply(exchange, {ack = ack})
    assert(#state.events == 0)
    API.Close(inst, "done")
end)
Test("manual takeover sends interruption and ignores late model commands", function()
    local inst, player, requests = Setup(); local state = Connect(inst, player, requests)
    Reply(requests[2], {commands = {{request_id = "move-1", skill = "move_to", arguments = {position = {x = 8, z = 0}}}}})
    state.poll.fn(); local pending = requests[#requests]
    API.Close(inst, "manual_command")
    local final = requests[#requests]
    assert(final.data.closing == "manual_command")
    local interrupted = false
    for _, event in ipairs(final.data.events) do if event.status == "interrupted" then interrupted = true end end
    assert(interrupted)
    Reply(pending, {commands = {{request_id = "late", skill = "move_to", arguments = {position = {x = 30, z = 0}}}}})
    assert(inst._my_friend_body == nil and inst.x == 0)
end)
Test("repeated HTTP timeouts disconnect the controller without retrying actions", function()
    local inst, player, requests = Setup(); local state = Connect(inst, player, requests)
    for i = 1, 3 do
        local timer = state.http_timeout
        timer.fn()
        if i < 3 then state.poll.fn() end
    end
    assert(inst._my_friend_body == nil)
    local before = #requests
    Reply(requests[2], {commands = {}})
    assert(#requests == before)
end)
Test("manual task keeps the transport; old HTTP instructions lose their revision and later user tasks can replace it", function()
    local inst, player, requests = Setup(); local state = Connect(inst, player, requests)
    API.ManualTakeover(inst); inst._my_friend_command = {id = "chop", player = player}
    Reply(requests[2], {commands = {{request_id = "stale", skill = "move_to", arguments = {position = {x = 8, z = 0}}}}})
    assert(inst._my_friend_body == state and state.active == nil and inst._my_friend_command.id == "chop")
    state.poll.fn()
    local current = requests[#requests]
    assert(current.data.snapshot.revision == 1 and current.data.snapshot.manual_task == "chop")
    Reply(current, {commands = {{request_id = "fresh", revision = 1, source = "direct", skill = "move_to", arguments = {position = {x = 6, z = 0}}}}})
    assert(state.active.request_id == "fresh" and inst._my_friend_command == nil)
    API.Close(inst, "done")
end)
Test("periodic context uses a 60-to-120-second randomized interval and bounded environment", function()
    local inst, player, requests = Setup(); local state = Connect(inst, player, requests)
    assert(requests[2].data.snapshot.environment.players[1].name == player:GetDisplayName())
    Reply(requests[2], {})
    fixture.advance(60)
    state.next_context = GetTime(); state.poll.fn()
    local current = requests[#requests]
    assert(state.next_context >= 220 and state.next_context <= 280)
    assert(current.data.snapshot.environment.players[1].name == player:GetDisplayName())
    local found = false; for _, event in ipairs(current.data.events) do found = found or event.kind == "ambient_context" end
    assert(found)
    assert(state.environment.position.x == inst.x)
    inst.x = inst.x + 5
    assert(API.Observation.Snapshot(inst,state).environment == nil)
    local count = #requests; assert(Bridge.Connect(inst, player, "481529")); assert(#requests == count)
    API.Close(inst, "done")
end)
Test("disabled model RPCs reserve the same IDs without serving requests", function()
    local inst, player, requests = Setup()
    local function Register(enabled)
        local order, handlers = {}, {}
        local function Capture(direction)
            return function(namespace, name, handler)
                order[#order + 1] = direction .. ":" .. namespace .. ":" .. name
                handlers[direction .. ":" .. name] = handler
            end
        end
        Bridge.Install({AddModRPCHandler = Capture("server"), AddClientModRPCHandler = Capture("client"),
            AddShardModRPCHandler = Capture("shard"), SendModRPCToShard = function() error("unexpected send") end}, enabled)
        return table.concat(order, ","), handlers
    end
    local enabled = Register(true)
    local disabled, handlers = Register(false)
    assert(enabled == disabled and #enabled > 0)
    handlers["server:BodyControl"](player, "connect", json.encode({code = "481529"}))
    handlers["client:BodyRelay"](json.encode({id = "test", path = "connect", payload = {}}))
    assert(not require("my_friend_body_chat").Forward(player, "hello", "rpc"))
    assert(#requests == 0 and inst._my_friend_body == nil)
end)
Test("RPC rejects forged players and oversized/invalid payloads", function()
    local inst, player, requests = Setup()
    local handlers, replies, relays = {}, {}, {}
    Bridge.Install({AddModRPCHandler = function(_, name, fn) handlers[name] = fn end,
        AddClientModRPCHandler = function() end, GetClientModRPC = function() return 1 end,
        SendModRPCToClient = function(_, _, payload)
            local value = json.decode(payload)
            if value.path ~= nil then relays[#relays + 1] = value else replies[#replies + 1] = value end
        end})
    local stranger = fixture.entity("wilson"); stranger.userid = "other"
    handlers.BodyControl(stranger, "connect", json.encode({code = "481529"}))
    handlers.BodyControl(player, "connect", string.rep("x", 4097))
    handlers.BodyControl(player, "connect", "not-json")
    assert(#requests == 0 and #replies == 1 and replies[1].reason == "permission_denied")
    handlers.BodyControl(player, "connect", json.encode({code = "481529"}))
    assert(#requests == 0 and #replies == 2 and #relays == 1)
    API.Close(inst, "done")
end)
Test("remote client makes local HTTP, authenticates relay receipts and loses stale control", function()
    local inst, player, requests = Setup()
    TheWorld.IsValid = function() return true end
    local server, client, wire = {}, {}, {}
    Bridge.Install({AddModRPCHandler = function(_, name, fn) server[name] = fn end,
        AddClientModRPCHandler = function(_, name, fn) client[name] = fn end,
        GetClientModRPC = function(_, name) return name end, GetModRPC = function(_, name) return name end,
        SendModRPCToClient = function(name, userid, payload)
            assert(type(userid) == "table" and #userid == 1 and userid[1] == player.userid)
            if name == "BodyRelay" then wire[#wire + 1] = json.decode(payload); client[name](payload) end
        end,
        SendModRPCToServer = function(name, payload) server[name](player, payload) end})
    server.BodyControl(player, "connect", json.encode({code = "481529"}))
    assert(#requests == 1 and requests[1].url == "http://127.0.0.1:18766/v1/game/connect")
    local stranger = fixture.entity("wilson"); stranger.userid = "other"
    server.BodyRelayReply(stranger, json.encode({id = wire[1].id, reply = {token = "forged"}}))
    assert(inst._my_friend_body.token == nil)
    Reply(requests[1], {token = "remote-token"})
    assert(#requests == 2 and requests[2].data.token == "remote-token")
    local state = inst._my_friend_body
    Reply(requests[2], {commands = {{request_id = "remote-move", skill = "move_to", arguments = {position = {x = 5, z = 0}}}}})
    assert(state.active.request_id == "remote-move")
    state.poll.fn(); local late = requests[#requests]
    API.Close(inst, "manual_command")
    assert(requests[#requests].data.closing == "manual_command")
    Reply(late, {commands = {{request_id = "late", skill = "move_to", arguments = {position = {x = 30, z = 0}}}}})
    assert(inst._my_friend_body == nil and inst.x == 0)
    local before = #requests
    client.BodyRelay(json.encode({id = "invalid", path = "http://elsewhere/", payload = {}}))
    assert(#requests == before)
end)
Test("listen host console connects directly with the actual local owner and no self RPC", function()
    local inst, player, requests = Setup()
    local previous_player = ThePlayer
    ThePlayer = player
    Bridge.Install({AddModRPCHandler = function() end, AddClientModRPCHandler = function() end,
        SendModRPCToServer = function() error("listen host must not send to itself") end})
    assert(Bridge.Control("start", "481529"))
    assert(#requests == 1 and inst._my_friend_body.owner == player and inst._my_friend_body.relay_owner == nil)
    Reply(requests[1], {token = "host-token"})
    assert(requests[2].data.token == "host-token")
    assert(Bridge.Control("stop") and inst._my_friend_body == nil)
    assert(not Bridge.Control("start", "bad") and inst._my_friend_body == nil)
    local stranger = fixture.entity("wilson"); stranger.userid = "stranger"
    ThePlayer = stranger
    local accepted, reason = Bridge.Control("start", "481529")
    assert(not accepted and reason == "permission_denied" and inst._my_friend_body == nil)
    ThePlayer = previous_player
end)
Test("dedicated server waits for an online player, retries outages, and uses its own loopback", function()
    local inst, player, requests = Setup()
    local net, local_player = TheNet, ThePlayer
    TheNet, ThePlayer = {IsDedicated = function() return true end}, nil
    inst.components.follower.GetLeader = function() return nil end
    AllPlayers = {}
    assert(not Bridge.TryDedicated(inst, "481529") and #requests == 0)
    AllPlayers = {player}
    assert(Bridge.TryDedicated(inst, "481529"))
    assert(inst._my_friend_body.dedicated and inst._my_friend_body.relay_owner == nil)
    requests[1].callback(nil, false, 0)
    assert(inst._my_friend_body == nil and not Bridge.TryDedicated(inst, "481529"))
    fixture.advance(10)
    assert(Bridge.TryDedicated(inst, "481529"))
    Reply(requests[2], {token = "dedicated-token"})
    Reply(requests[3], {})
    local state = inst._my_friend_body
    assert(state.ready and requests[3].data.token == "dedicated-token")
    local guest = fixture.entity("wilson")
    guest.userid, AllPlayers = "guest", {guest}
    state.poll.fn()
    assert(inst._my_friend_body == nil)
    fixture.advance(10)
    assert(Bridge.TryDedicated(inst, "481529") and inst._my_friend_body.owner == guest)
    API.Close(inst, "done")
    TheNet, ThePlayer = net, local_player
end)
Test("dedicated code mismatch stops retries until an explicit restart of pairing", function()
    local inst, _, requests = Setup()
    local net, local_player = TheNet, ThePlayer
    TheNet, ThePlayer = {IsDedicated = function() return true end}, nil
    assert(Bridge.TryDedicated(inst, "000000"))
    requests[1].callback(nil, false, 403)
    assert(inst._my_friend_body == nil)
    fixture.advance(60)
    assert(not Bridge.TryDedicated(inst, "000000") and #requests == 1)
    assert(Bridge.Control("start", "481529"))
    assert(requests[2].data.code == "481529")
    API.Close(inst, "done")
    TheNet, ThePlayer = net, local_player
end)
Test("opt-in local player auto-connect wiring receives success and reconnects after a real session loss", function()
    local inst, player, requests = Setup(); local previous = ThePlayer; ThePlayer = player
    Bridge.Install({AddModRPCHandler = function() end, AddClientModRPCHandler = function() end,
        SendModRPCToServer = function() error("local host must connect directly") end})
    local before = #player.tasks
    Bridge.AttachAuto(player, false, "321151"); assert(#player.tasks == before)
    Bridge.AttachAuto(player, true, "321151")
    player.tasks[#player.tasks].fn()
    player.tasks[#player.tasks].fn()
    assert(requests[1].data.code == "321151")
    Reply(requests[1], {token = "auto-token"})
    Reply(requests[2], {})
    assert(inst._my_friend_body.token == "auto-token")
    API.Close(inst, "bridge_unavailable")
    local retry = player.tasks[#player.tasks]; assert(retry.delay == 0); retry.fn()
    assert(requests[#requests].data.code == "321151")
    API.Close(inst, "cleanup"); player:PushEvent("onremove")
    assert(player.tasks[#player.tasks].cancelled)
    ThePlayer = previous
end)
Test("assistant text is validated once by native names and carries a bound input context back to actions",function()
    local inst,p,requests=Setup()
    Bridge.Install({AddModRPCHandler=function()end,AddClientModRPCHandler=function()end,
        GetClientModRPC=function()return 1 end,SendModRPCToClient=function()end})
    local state=Connect(inst,p,requests)
    assert(requests[1].data.input_protocol==2)
    Reply(requests[2],{inputs={{id="text-1",text="温蒂，跑到旁边"}}})
    local event
    for _,e in ipairs(state.events)do if e.kind=="player_input"then event=e end end
    assert(event and event.speaker.userid==p.userid and event.input_id=="text-1")
    state.poll.fn()
    Reply(requests[#requests],{inputs={{id="text-1",text="温蒂，跑到旁边"}},commands={{request_id="bound-move",skill="move_to",
        source="user",turn_id=event.turn_id,arguments={position={x=3,z=0}}}}})
    fixture.perform(inst)
    assert(state.jobs[state.requests["bound-move"].id].status=="completed")
    local count=0;for _,e in ipairs(state.events)do if e.kind=="player_input"then count=count+1 end end
    assert(count==1)
    state.poll.fn();Reply(requests[#requests],{inputs={{id="bad-text",text=string.rep("x",2049)}},finished_inputs={event.turn_id},
        commands={{request_id="unbound",skill="move_to",source="user",arguments={position={x=9,z=0}}}}})
    assert(state.inputs[event.turn_id]==nil and state.active==nil and inst.x==3)
    local rejected,unbound=false,false
    for _,e in ipairs(state.events)do rejected=rejected or e.kind=="input_rejected" and e.reason=="invalid_text"
        unbound=unbound or e.request_id=="unbound" and e.reason=="invalid_input_context"end
    assert(rejected and unbound)
    API.Close(inst,"done")
end)
Test("a room player shares an existing assistant without stealing its transport or requiring follow",function()
    local inst,p,requests=Setup();inst.components.follower.GetLeader=function()return nil end;p.x=100
    local state=Connect(inst,p,requests);Reply(requests[2],{})
    local other=fixture.entity("wilson");other.userid="other";AllPlayers[#AllPlayers+1]=other
    Bridge.Install({AddModRPCHandler=function()end,AddClientModRPCHandler=function()end,
        GetClientModRPC=function()return 1 end,SendModRPCToClient=function()end})
    local before=#requests;assert(Bridge.Connect(inst,other,"481529"))
    assert(state.owner==p and API.Valid(inst)==state and #requests==before and state.observers[other]~=nil)
    API.Close(inst,"done")
end)
print(string.format("%d body transport tests passed", passed))
