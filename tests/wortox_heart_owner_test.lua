-- Run from the mod root: lua tests/wortox_heart_owner_test.lua
package.path = "scripts/?.lua;" .. package.path

package.loaded.my_friend_policy = {}
package.loaded.my_friend_dialogue = {}

local function Owner(prefab, tags)
    local owner = {
        prefab = prefab, _my_friend_id = "shared", components = {
            skilltreeupdater = {IsActivated = function() return true end},
        },
    }
    function owner:IsValid() return true end
    function owner:HasTag(tag) return tags[tag] == true end
    function owner:GetDisplayName() return prefab end
    function owner:ListenForEvent() end
    return owner
end

local player = Owner("wilson", {my_friend_possessed = true})
local friend = Owner("wortox", {my_friend = true})
AllPlayers = {player}
TheWorld = {ismastersim = true, _my_friend = friend}

local owner_name = ""
local linked = {
    netownername = {
        value = function() return owner_name end,
        set = function(_, value) owner_name = value end,
    },
}
function linked:GetOwnerUserID() return nil end
function linked:GetOwnerInst() return self.owner_inst end
function linked:SetOwnerInst(owner) self.owner_inst = owner end
function linked:OnSkillTreeInitialized() end

local heart = {components = {linkeditem = linked}}
function heart:IsValid() return true end
function heart:TryToAttachWortoxID() end
function heart:SetAllowConsumption(allow) self.allow = allow end
function heart:ListenForEvent() end
function heart:RemoveEventCallback() end

local Wortox = require("my_friend_wortox")
Wortox.ConfigureHeart(heart)
heart:TryToAttachWortoxID(friend)
assert(linked:GetOwnerInst() == friend and heart.allow == true)

-- The controlled body shares the session id but is not the heart's maker.
heart._my_friend_heart_owner = nil
linked.owner_inst = nil
assert(linked:GetOwnerInst() == friend and heart.allow == true)

-- Even if both bodies are Wortox, keep the still-living maker.
player.prefab = "wortox"
Wortox.RefreshLinkedHearts(player)
assert(linked:GetOwnerInst() == friend and heart.allow == true)
print("PASS: a companion-made heart stays linked to its Wortox maker")
