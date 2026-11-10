"""Provider-neutral tool descriptions. No model, SDK or executable model output."""
def field(kind, description="", **options):
    return {"type": kind, "description": description, **options}


HANDLE = field("string", "Entity identity within this game connection. No time expiry; removal, bounded-cache eviction or reconnect can invalidate it. Actions always recheck live state and ownership.")
COUNT = field("integer", "Requested quantity, from 1 to 40.", minimum=1, maximum=40)
MIX = field("array", "Exactly four ingredient prefab IDs per pot, repeated for repeated slots. Validate using query_recipe(kind=cook) first.", minItems=4, maxItems=4, items=field("string", maxLength=80))
POSITION = field("object", "Game coordinates, not pixels or metres.", properties={
    "x": field("number"), "z": field("number")}, required=["x", "z"], additionalProperties=False)
DEFINITIONS = [
    ("query_batch", "Run up to 8 independent read-only queries in one game request, returning id/status/result/reason for each. Use the current inventory snapshot, then combine nearby items, accessible container contents, recipes and known-target native action checks. Nested operations are limited to observe/query_recipe/query_sites/query_actions/get_capabilities. No movement or world operations. Results may be limited/truncated; missing data in a limited result is unknown, not absence.", {
        "queries": field("array",minItems=1,maxItems=8,items=field("object",properties={
            "id":field("string",maxLength=40), "skill":field("string",enum=["observe","query_recipe","query_sites","query_actions","get_capabilities"]),
            "arguments":field("object",additionalProperties=True)},required=["skill","arguments"],additionalProperties=False))}, ["queries"]),
    ("execute_sequence", "Run decided steps locally, stopping at the first failure. Ordinary arguments can reference individual results such as $dig.drop.handle or $site.sites.1.position. A repeat block has id, for_each and steps; for_each is an explicit JSON array of values, never a string such as $site.sites. For a list of unknown length, query it first and build the array in the next call. Templates use $each or $each.field. Up to 40 values, 12 templates and 64 expanded steps, one repeat level. Read completed/failed_step and retry only unfinished work. World/role/follow/engage/delegated actions stay standalone.", {
        "steps": field("array", minItems=1, maxItems=64, items=field("object", properties={
            "id": field("string", maxLength=40, pattern="^[A-Za-z0-9_]+$"),
            "skill": field("string", enum=["observe","query_recipe","query_sites","query_actions","get_capabilities","move_to","pickup","drop","transfer","equip","unequip","craft","work","eat","cook","use_item","interact","harvest","perform_action","pickup_many","work_many","dismount","emote","revive"]),
            "arguments": field("object", additionalProperties=True),
            "for_each": field("array", "List the iteration values in an array. Resolve variable-length query results before sending the sequence.", minItems=1, maxItems=40, items={}),
            "steps": field("array", minItems=1, maxItems=12, items=field("object", properties={
                "id": field("string"), "skill": field("string"), "arguments": field("object", additionalProperties=True)},
                required=["id","skill","arguments"], additionalProperties=False))}, required=["id"], additionalProperties=False))}, ["steps"]),
    ("query_sites", "Sample up to 64 nearby positions using native placement rules; return up to 8 spaced valid candidates with nearby structures. Supply either a building recipe or a carried deployable item handle. Optional position sets the search centre (within 32); radius 1..16 defaults 12. Tile deployables use tile centres. For a requested ground build site, player_occupies_site indicates current player occupancy separately from native validity. Choose a location that meets player intent; ask if the intended area is unclear or no suitable candidate exists. Recheck the requested site after failure.", {
        "recipe": field("string"), "item": HANDLE, "position": POSITION,
        "radius": field("number", minimum=1, maximum=16),
        "exact": field("boolean", "With position, validate only that point. Default also searches alternatives. A valid explicit centre is the first candidate; blocked requested_site includes native validity and nearby obstacle context."),
        "action": field("string", "Optional native action filter. TILL requires the handle of a carried hoe (farm_tiller=true)."),
        "layout": field("object", "Use rows and columns for a fixed grid, or ring for equally spaced points at radius from position. With TILL and tile=true, anchor to the observed farm tile and use the built-in 3x3 spacing across adjacent tiles. rows=2,columns=3 selects two rows on one tile; columns=6 extends them across two tiles. Use rotation=0 or 90 to follow the field. sites contains only places to till; cells may report already_tilled with a hole handle.", properties={
            "rows": field("integer", minimum=1, maximum=40), "columns": field("integer", minimum=1, maximum=40),
            "ring": field("integer", minimum=3, maximum=40),
            "spacing": field("number", exclusiveMinimum=0), "rotation": field("number"), "tile": field("boolean")},
            additionalProperties=False)}, []),
    ("query_actions", "Discover current native actions for item/target/point. A position can resolve a nearby scene target within 0.6. Crop seeds prefer open soil; use the exact hole handle from observe(scope=farm) for PLANTSOIL. INVENTORY=self-use; USEITEM=item on entity; EQUIPPED=hand item on entity, equip first; POINT=ground point; SCENE=world entity. Empty actions means this combination is currently unavailable.", {
        "item": HANDLE, "target": HANDLE, "position": POSITION,
        "mode": field("string", enum=["INVENTORY", "EQUIPPED", "USEITEM", "POINT", "SCENE"]),
        "right": field("boolean", "Default true; false queries left-click uses where applicable.")}, []),
    ("perform_action", "Execute a native action with matching item/target/point/right. TILL uses POINT at a query_sites location and returns the new soil.handle. Crop seeds use PLANTSOIL in USEITEM mode with the exact open soil handle. Tree seeds and transplants use their native deploy action. Native availability, costs, cooldowns and role/PVP rules are rechecked. Native GIVE uses trader stack rules.", {
        "action": field("string", maxLength=80), "mode": field("string", enum=["INVENTORY", "EQUIPPED", "USEITEM", "POINT", "SCENE"]),
        "item": HANDLE, "target": HANDLE, "position": POSITION, "right": field("boolean")}, ["action", "mode"]),
    ("observe", "Live local scan. Use scope=scene with the intended work position and radius 4 to 8 to inspect objects around a site, including loose items, debris, walls, ground holes and other physical objects. Scene radius defaults to 8 and caps at 16; entities are limited to 32 units from the companion. area_clipped means part of the requested area is outside that range. scope=farm returns tile bounds, open holes and weed counts. target_type=weed finds all weeds; action=DIG limits it to diggable targets. Follow next_offset for more tiles or entities. Use target plus optional radius to refresh a handle. Containers support contents pagination.", {
        "scope": field("string", enum=["nearby", "inventory", "all", "structures", "creatures", "players", "containers", "items", "interactions", "terrain", "farm", "boats", "scene"]),
        "position": {**POSITION, "description": "Optional centre for scope=scene only, within 32 units of the companion."},
        "target": field("string", "Refresh one nearby handle; combine only with an optional radius.", maxLength=32),
        "action": field("string", "Filter workable targets before pagination; scope must be omitted, nearby, all or scene.", enum=["CHOP","MINE","DIG","HAMMER","PICK","HARVEST"]),
        "target_type": field("string", enum=["tree", "weed"]),
        "filter": field("string", "Substring of localized name or prefab, e.g. researchlab3 for Shadow Manipulator."),
        "radius": field("number", minimum=1, maximum=32), "contents": field("boolean"),
        "offset": field("integer", "Entity page offset from next_offset; keep other filters unchanged.", minimum=0, maximum=10000),
        "container": field("string", "Exact container handle, only with scope=containers.", maxLength=32),
        "contents_offset": field("integer", "Contents page offset from contents_next_offset; requires container and contents=true.", minimum=0, maximum=10000)}, []),
    ("get_capabilities", "Query native_commands coverage (composable/native_action_only/not_exposed; command IDs are not callable tools) and this character's callable role.actions, passive role.automatic, special role.recipes and equipment_slots. item_actions is a legacy subset; query_actions discovers native item uses. Never invent role abilities.", {}, []),
    ("character_skill", "Run an existing mod role action listed by get_capabilities.role.actions, reusing its original script. Supports Abigail modes/recall, role recipes/devices, bookshelf-aware reading, seasoning, lightning spear, Wortox heart operations and Wormwood carried medicine. Bookcases and Sisturns use the player's tile centre at the start of the command. If that site stays blocked, the tool returns placement_blocked. Availability and original conservation/cost rules still apply.", {
        "ability": field("string", maxLength=80), "recipe": field("string", maxLength=80),
        "food": HANDLE, "spice": HANDLE}, ["ability"]),
    ("query_recipe", "Read live craft/cook recipes. Craft returns costs, sources, technology, stations and placement. technology_status.permanently_unlocked is the saved recipe unlock; known and satisfied reflect current access. allows_permanent_unlock describes whether prototyping can record a lasting unlock; manufactured requires an active compatible station every time. Cook: count=pots; optional ingredients=four prefab IDs validates a per-pot mix before gathering. Returns mix, deficits, sources, unavailable and stations. valid_mix is recipe validity; materials_ready is carried supply for all pots. Explicit fresh jerky requires a player request. Estimated outputs are not actual production.", {
        "query": field("string", maxLength=120), "kind": field("string", enum=["craft", "cook"]),
        "station": field("string", "Optional observed cooking-station handle; only used for kind=cook."), "count": COUNT, "ingredients": MIX}, ["query"]),
    ("move_to", "Travel to one known handle, land/deck position, or named destination on this shard. Uses long land routes, deck walking and native hops. A boat handle means board; shore means disembark. For a water target handle, approach within distance from a reachable shore or deck. Positions must be walkable; open water has no walking route. Completion confirms actual arrival/surface. Boats must already be within jumping/interaction reach; no automatic sailing.", {
        "target": HANDLE, "position": POSITION, "destination": field("string", enum=["base", "speaker", "shore"]),
        "gait": field("string", enum=["walk", "run"]),
        "distance": field("number", minimum=.3, maximum=12)}, []),
    ("pickup", "Take a loose item or an accessible container slot item. Call directly on a known item. Automatically approaches, including docks, decks and reachable native hops; floating items use native pickup reach. On no_surface_in_reach, no_boarding_point or boat_unreachable, refresh the target or change access before retrying. Default one from containers, whole loose stack; count requests an exact amount. Shared storage needs its physical opening as container. Backpacks equip and replace the old bag; heavy items use the carry controller.", {
        "target": HANDLE, "count": COUNT, "container": HANDLE}, ["target"]),
    ("pickup_many", "Pick up multiple nearby loose stacks in one game-local job, then return actual totals and failures once. Automatic scans stay on the current platform; explicit targets can use the same shore and deck approaches as pickup. One initial scan; new drops need another batch. Heavy objects require individual pickup.", {
        "targets": field("array", "Optional observed handles; omit to scan matching ground items once.", items=HANDLE, maxItems=100),
        "filter": field("string", "Name/prefab substring; empty selects all eligible ground items.", maxLength=120),
        "radius": field("number", minimum=1, maximum=32)}, []),
    ("drop", "Drop carried or worn items, optionally at position. Returns item_state with the actual ground handle/location. Backpacks retain contents and are released from automatic recovery. Use to hand over the ORIGINAL worn bag before picking up a replacement.", {"item": HANDLE, "count": COUNT, "position": POSITION}, ["item"]),
    ("transfer", "Move carried storable items to a living player or accessible container, or from nested storage to snapshot.handle. Automatically approaches and opens/closes storage. Use revive for a ghost with a Telltale Heart; drop backpacks near the recipient. Check actual count/partial.", {"item": HANDLE, "destination": HANDLE, "count": COUNT}, ["item", "destination"]),
    ("equip", "Equip an owned item; does not re-equip an already equipped item.", {"item": HANDLE}, ["item"]),
    ("unequip", "Remove the exact slot from inventory.slot or get_capabilities.equipment_slots, including supported extra slots. Backpacks may drop to ground under native rules.", {"slot": field("string", maxLength=80)}, ["slot"]),
    ("craft", "Craft using carried materials. Omit station by default; the game crafts locally when technology is satisfied and approaches a suitable nearby station when needed. A successful prototype of a learnable recipe unlocks future crafting. Recheck live technology for recipes that cannot be permanently learned. For buildings, auto prepares and places at an explicit position. mode=prepare spends materials and keeps one buffered build per recipe; mode=place uses it without more materials or local tech. On land the companion may try to clear an occupying player by walking, then rechecks the same point. placement_blocked preserves the prepared build and returns placement details. If player_occupies_site is true, ask the player to step aside before retrying that point. Use distinct points for multiple buildings. Deploy portable products separately.", {
        "recipe": field("string"), "count": COUNT, "position": POSITION,
        "station": field("string", "Set only to deliberately use a particular observed station. Passing its handle can make the companion travel there even when it can craft locally."),
        "mode": field("string", enum=["auto", "prepare", "place"])}, ["recipe"]),
    ("work", "PICK/HARVEST once; CHOP/MINE/DIG/HAMMER until target finished unless amount specified. Requires a carried tool. Optional drop_prefab binds loot emitted by this actual work action as result.drop; use $dig.drop.handle in the next sequence step. Missing/removed expected loot stops the sequence. Other ground_items are nearby changes and may include unrelated items. Carried raw materials must be dropped before working.", {
        "target": HANDLE, "action": field("string", enum=["CHOP", "MINE", "DIG", "HAMMER", "PICK", "HARVEST"]),
        "drop_prefab": field("string", "Expected native dropped prefab, e.g. dug_grass; only use a known output.", maxLength=80),
        "amount": COUNT}, ["target", "action"]),
    ("work_many", "Work on nearby matching targets. Use CHOP with target_type=tree, or DIG with target_type=weed to remove weeds of any species. For a particular plot pass its observed targets. Counted jobs default to radius 32, stop on failure and report requested/targets/remaining. Without count, work over all discovered targets on a best-effort basis. Requires tools.", {
        "targets": field("array", items=HANDLE, maxItems=100), "filter": field("string", maxLength=120),
        "count": COUNT, "target_type": field("string", enum=["tree", "weed"]),
        "radius": field("number", minimum=1, maximum=32),
        "action": field("string", enum=["CHOP", "MINE", "DIG", "HAMMER", "PICK", "HARVEST"])}, ["action"]),
    ("eat", "Eat one carried item under character diet and low-health protection; rejects health-damaging food at low health or if it would leave only a small health margin. Returns actual stat deltas. Check freshness and food.health/hunger/sanity; stale or spoiled food may not heal. Never use calories alone as healing.", {"item": HANDLE}, ["item"]),
    ("cook", "Cook ONE pot of recipe using carried ingredients. Supply validated four-slot ingredients to preserve the chosen mix (and explicit requested jerky); otherwise choose automatically. Default waits and harvests, returning actual product items. wait=false only starts cooking. For two meals call twice and transfer actual product counts; ready pots use harvest.", {
        "recipe": field("string"), "station": HANDLE, "ingredients": MIX, "wait": field("boolean", "Default true: wait and harvest. false: finish after starting; start other devices, then harvest later.")}, ["recipe", "station"]),
    ("harvest", "Collect from a ready pot. wait=true waits locally if it is still cooking; recipe guards against harvesting the wrong product. Returns actual product handles.", {
        "target": HANDLE, "wait": field("boolean"), "recipe": field("string")}, ["target"]),
    ("use_item", "Use a legacy item action or a native action id/mode from query_actions. READ needs a reader, CAST_POCKETWATCH needs Wanda and a ready watch. A casting point is a destination for the effect, not a movement instruction.", {
        "item": HANDLE, "target": HANDLE, "position": POSITION,
        "mode": field("string", enum=["INVENTORY", "EQUIPPED", "USEITEM", "POINT"]), "right": field("boolean"),
        "action": field("string", "Legacy uses or an actual action id returned by query_actions.", maxLength=80)}, ["item"]),
    ("interact", "Use a target interaction or SCENE action returned by query_actions. SITON delegates to normal seating and completes only when seated.", {
        "target": HANDLE, "action": field("string", "Known scene interaction or a SCENE action returned by query_actions.", maxLength=80)}, ["target", "action"]),
    ("emote", "Play a vanilla gesture once, including sit on the ground. A request to sit in a chair uses interact SITON.", {
        "emote": field("string", enum=["sit", "squat", "wave", "happy", "cry", "dance", "angry", "no", "joy", "pose"])}, ["emote"]),
    ("dismount", "Get off the current mount and verify the companion is on foot.", {}, []),
    ("revive", "Apply a carried reviver (such as a Telltale Heart, prefab reviver) to a same-shard player ghost using native revival. Check ghost state; do not transfer the heart to their inventory.", {
        "target": HANDLE, "item": HANDLE}, ["target", "item"]),
    ("engage", "Continuously pursue and attack this live creature until it dies, is cancelled, or is interrupted. Tracks moving targets; call engage directly after observe, without move_to first. Uses existing weapon, survival, dodge and follow-distance rules.", {"target": HANDLE}, ["target"]),
    ("disengage", "Stop the current interface action and use normal follow disengagement.", {}, []),
    ("follow", "Resume original background following for the actual speaker by default; completes immediately without occupying a body job. Work and idle life remain available. Use move_to for precise positioning.", {
        "player": HANDLE, "distance": field("number", "Compatibility argument; actual distance uses the original companion follow rules. Use move_to for a precise position.", minimum=1, maximum=20)}, []),
    ("say", "Speak once and END the model turn. Do not use for a pre-action announcement; attach text to the body skill instead. A response containing both text and say produces one utterance. Optional local speech; no item action is implied.", {
        "text": field("string", maxLength=180), "speak": field("boolean")}, ["text"]),
    ("cancel", "Request cancellation without forcing a busy native animation.", {"action_id": field("string")}, ["action_id"]),
    ("get_action_status", "Read an interface action's actual status and result.", {"action_id": field("string")}, ["action_id"]),

    ("save_game", "Request native save through mandatory two-message reason review. First call creates needs_reason/approval_id only. After the same player answers, submit that id, exact utterance as reason, approved and assessment. No administrator grants.", {
        "approval_id": field("string"), "reason": field("string", "Copy this turn's exact utterance."),
        "approved": field("boolean"), "assessment": field("string", "Model's explanation of whether the reason is reasonable.",maxLength=200)}, []),
    ("rollback_game", "Same mandatory reason review as save_game; count defaults to 1 snapshot and must stay unchanged across review. requested=true schedules rollback, not completed restoration; end the turn and never replay.", {
        "count": field("integer",minimum=1,maximum=2147483647), "approval_id": field("string"), "reason": field("string"),
        "approved": field("boolean"), "assessment": field("string",maxLength=200)}, []),
    ("pause_game", "Pause/resume only after the same reason-review flow. Keep paused unchanged across review; default true. End the turn after requested=true.", {
        "paused": field("boolean"), "approval_id": field("string"), "reason": field("string"),
        "approved": field("boolean"), "assessment": field("string",maxLength=200)}, []),
    ("kick_player", "Kick an exact online userid only after the reason-review flow. Resolve names uniquely via world_control.players. Kick is distinct from permanent ban; never guess a userid or act unsolicited.", {
        "userid": field("string",maxLength=128), "approval_id": field("string"), "reason": field("string"),
        "approved": field("boolean"), "assessment": field("string",maxLength=200)}, ["userid"]),
    ("ban_player", "Add an exact online userid to the native server ban list only after reason review. A permanent ban requires stronger justification than a kick; reject unsupported or frivolous reasons. Never act unsolicited.", {
        "userid": field("string",maxLength=128), "approval_id": field("string"), "reason": field("string"),
        "approved": field("boolean"), "assessment": field("string",maxLength=200)}, ["userid"]),
]
TOOLS = [{"name": name, "description": description, "parameters": {
    "type": "object", "properties": properties, "required": required, "additionalProperties": False}}
    for name, description, properties, required in DEFINITIONS]
NAMES = {tool["name"] for tool in TOOLS}


def compact_arguments(value):
    """Drop provider-null optional fields before encoding native Lua arguments."""
    if isinstance(value, dict):
        return {k: compact_arguments(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [compact_arguments(v) for v in value]
    return value
