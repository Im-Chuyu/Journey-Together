local Policy = require("my_friend_policy")
local Sitting = require("my_friend_sitting")
local RouteAction = require("behaviours/my_friend_route_action")
local M = {}
local function Context(inst)
    local service = TheWorld ~= nil and TheWorld._my_friend_games or nil
    local leader = Policy.GetLeader(inst)
    if service == nil or TheWorld._my_friend ~= inst or leader == nil or leader.userid == nil then return end
    local game = service:Current(leader.userid)
    if game ~= nil and (game.state.status == "playing" or game.state.status == "scoring") and service:Companion(game) == inst
        and service:CanPlay(leader) then return leader, game end
end
function M.Score(inst, context)
    local leader = Context(inst)
    if leader == nil or Policy.IsRoaming(inst) or inst:HasTag("sitting_on_chair") or inst:HasTag("wereplayer")
        or inst.sg == nil or inst.sg.HasState ~= nil and not inst.sg:HasState("emote")
        or not Sitting.Available(inst, context)
        or leader.sg ~= nil and leader.sg:HasStateTag("moving") then return 0 end
    return 13
end
local GameSit = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendGameSit")
    self.inst = inst
end)
function GameSit:StopRoute()
    local route = self.route
    if route == nil then return end
    local action = route.action
    if action ~= nil and route.pendingstatus == nil then
        action._my_friend_cancelled = true
        action:Fail()
        if self.inst:GetBufferedAction() == action then self.inst:ClearBufferedAction() end
    end
    route:Stop(); self.route = nil
end
function GameSit:StopEmote()
    local sg = self.inst.sg
    -- Only leave the cosmetic loop we own, after vanilla's .5s pre-animation.
    if self.memory ~= nil and sg ~= nil and sg.currentstate.name == "emote"
        and sg.statemem == self.memory and not Policy.IsBusy(self.inst) then sg:GoToState("idle") end
    self.memory = nil
end
function GameSit:Visit()
    local inst = self.inst
    local leader, game = Context(inst)
    if leader == nil or M.Score(inst) == 0 then self.status = FAILED return end
    if Policy.IsBusy(inst) then self.status = RUNNING; self:Sleep(.15); return end
    self.status = RUNNING
    local distance = Policy.DistanceSq(inst, leader)
    if distance > (self.memory ~= nil and 3.5^2 or 2.75^2) then
        self:StopEmote()
        if self.route == nil or self.leader ~= leader or self.game ~= game.id then
            self:StopRoute()
            local id = game.id
            self.route = RouteAction(inst, function()
                local current, match = Context(inst)
                if current ~= leader or match == nil or match.id ~= id then return end
                local action = BufferedAction(inst, leader, ACTIONS.WALKTO)
                action.arrivedist = 2.5
                return Policy.GuardAction(inst, action)
            end, "ApproachBoardGamePlayer", false, 12, true)
        end
        self.leader, self.game = leader, game.id
        self.route:Visit()
        if self.route.status == FAILED then self.status = FAILED end
    else
        self:StopRoute()
        if self.memory == nil or inst.sg.currentstate.name ~= "emote" or inst.sg.statemem ~= self.memory then
            local common = GetCommonEmotes ~= nil and GetCommonEmotes() or {}
            local definition = common.sit ~= nil and common.sit.data or nil
            if definition == nil then self.status = FAILED return end
            local data = {}; for k, v in pairs(definition) do data[k] = v end
            data.zoom = nil
            inst.components.locomotor:Stop()
            inst.sg:GoToState("emote", data)
            self.memory = inst.sg.statemem
        end
        require("my_friend_base_ai").SetTask(inst, require("my_friend_games_strings").Get("game_sit_task"))
    end
    self:Sleep(.25)
end
function GameSit:OnStop()
    self:StopRoute(); self:StopEmote()
    self.leader, self.game = nil, nil
end
M.Behaviour = GameSit
return M
