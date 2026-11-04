-- Coverage audit, not an arbitrary chat-command execution gateway.
local M = {}
local ROUTES={
    follow={"follow"},stop_task={"cancel"},sit={"emote","interact"},backpack={"pickup"},
    stop_ride={"dismount"},
    backpack_drop={"drop"},food={"eat"},equipment={"pickup","equip"},
    carry_statue={"pickup","move_to","drop"},
    chop={"work_many"},mine={"work_many"},harvest={"work_many"},grass={"work_many"},
    dig_grass={"work_many"},dig_sapling={"work_many"},dig_stump={"work_many"},
    seeds={"pickup_many"},tidy={"pickup_many","transfer"},
    plant_trees={"query_sites","perform_action"},hoe={"query_sites","perform_action"},
    water={"query_actions","perform_action"},dry_meat={"transfer"},
    rockfruit={"query_actions","work"},bullkelp={"query_actions","work"},
    monkeytail={"work"},banana={"work"},butterfly={"engage"},
    squeeze_heart={"character_skill"},
}
local PARTIAL={fish=true,ride=true,touch_tower=true,stop_sit=true}
function M.Get(inst)
    local commands=require("my_friend_commands")
    local out={}
    for _,entry in ipairs(commands.Catalogue~=nil and commands.Catalogue(inst) or {})do
        out[#out+1]={id=entry.id,coverage=ROUTES[entry.id]~=nil and "composable"
            or PARTIAL[entry.id] and "native_action_only" or "not_exposed",
            interfaces=ROUTES[entry.id] or PARTIAL[entry.id] and {"query_actions","perform_action"} or nil}
    end
    return {commands=out,other_unexposed={"rename","pet_adoption","farewell_switch"},note="Coverage describes available primitives, not identical autonomous policies. native_action_only does not promise the original continuous controller. not_exposed cannot be invoked by sending its ID. Role abilities are listed separately in role.actions."}
end
return M
