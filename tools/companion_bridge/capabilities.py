"""Provider-neutral tool descriptions. No model, SDK or executable model output."""
def field(kind, description="", **options):
    return {"type": kind, "description": description, **options}


HANDLE = field("string", "Current entity handle; expiry and current ownership still apply.")
COUNT = field("integer", "Requested quantity, from 1 to 40.", minimum=1, maximum=40)
MIX = field("array", "Exactly four ingredient prefab IDs per pot, repeated for repeated slots. Validate using query_recipe(kind=cook) first.", minItems=4, maxItems=4, items=field("string", maxLength=80))
POSITION = field("object", "Game coordinates, not pixels or metres.", properties={
    "x": field("number"), "z": field("number")}, required=["x", "z"], additionalProperties=False)
DEFINITIONS = [
    ("query_batch", "Run up to 8 independent read-only queries in one game request, returning id/status/result/reason for each. Use the current inventory snapshot, then combine nearby items, accessible container contents, recipes and known-target native action checks. Nested operations are limited to observe/query_recipe/query_sites/query_actions/get_capabilities. No movement or world operations. Results may be limited/truncated; missing data in a limited result is unknown, not absence.", {
        "queries": field("array",minItems=1,maxItems=8,items=field("object",properties={
            "id":field("string",maxLength=40), "skill":field("string",enum=["observe","query_recipe","query_sites","query_actions","get_capabilities"]),
            "arguments":field("object",additionalProperties=True)},required=["skill","arguments"],additionalProperties=False))}, ["queries"]),
    ("execute_sequence", "Run decided steps locally; stop at first failure and preserve progress. Up to 64 expanded steps. Reference earlier results as $id.items.1.handle or $id.entities.1.handle (no .result). Repetition: {id,for_each:[values],steps:[templates]}; templates use $each or $each.field, and local result references are namespaced per iteration. One repeat level, <=40 values, <=12 templates; no scripts/conditions. Use to apply a checked layout or several targets without model round-trips. Inspect completed/failed_step/steps; retry only unfinished work. World/role/follow/engage/delegated actions remain standalone.", {
        "steps": field("array", minItems=1, maxItems=64, items=field("object", properties={
            "id": field("string", maxLength=40, pattern="^[A-Za-z0-9_]+$"),
            "skill": field("string", enum=["observe","query_recipe","query_sites","query_actions","get_capabilities","move_to","pickup","drop","transfer","equip","unequip","craft","work","eat","cook","use_item","interact","harvest","perform_action","pickup_many","work_many","dismount","emote","revive"]),
            "arguments": field("object", additionalProperties=True),
            "for_each": field("array", minItems=1, maxItems=40, items={}),
            "steps": field("array", minItems=1, maxItems=12, items=field("object", properties={
                "id": field("string"), "skill": field("string"), "arguments": field("object", additionalProperties=True)},
                required=["id","skill","arguments"], additionalProperties=False))}, required=["id"], additionalProperties=False))}, ["steps"]),
    ("query_sites", "Sample up to 64 nearby positions using native placement rules; return up to 8 spaced valid candidates with nearby structures. Supply either a building recipe or a carried deployable item handle. Optional position sets the search centre (within 32); radius 1..16 defaults 12. Tile deployables use tile centres. Candidates describe physical validity, not player intent, safe access or reserved space. Choose a useful location; ask the player if the intended area is unclear or no suitable candidate exists. Requery only the blocked area after failure.", {
        "recipe": field("string"), "item": HANDLE, "position": POSITION,
        "radius": field("number", minimum=1, maximum=16),
        "action": field("string", "Optional native action filter, e.g. TILL. Supports carried tools as well as deployables."),
        "layout": field("object", "Use rows and columns for a fixed grid, or ring for equally spaced points at radius from position. Blocked cells are reported. tile=true centres a grid on the terrain tile.", properties={
            "rows": field("integer", minimum=1, maximum=40), "columns": field("integer", minimum=1, maximum=40),
            "ring": field("integer", minimum=3, maximum=40),
            "spacing": field("number", exclusiveMinimum=0), "rotation": field("number"), "tile": field("boolean")},
            additionalProperties=False)}, []),
    ("query_actions", "Discover current native actions for item/target/point. A position can resolve the nearest scene target within 0.6; omit mode to discover both point and entity uses, including soil planting. Return target/item/position and action modes for references. INVENTORY=self-use; USEITEM=item on entity; EQUIPPED=hand item on entity, equip first; POINT=ground point; SCENE=world entity. uses and interactions are partial hints, not a complete action list. Empty actions means this combination is currently unavailable.", {
        "item": HANDLE, "target": HANDLE, "position": POSITION,
        "mode": field("string", enum=["INVENTORY", "EQUIPPED", "USEITEM", "POINT", "SCENE"]),
        "right": field("boolean", "Default true; false queries left-click uses where applicable.")}, []),
    ("perform_action", "Execute an action/mode returned by query_actions with matching item/target/point/right. Native availability, costs, cooldowns and role/PVP rules are rechecked. Prefer dedicated interfaces when listed. Native GIVE uses trader stack rules.", {
        "action": field("string", maxLength=80), "mode": field("string", enum=["INVENTORY", "EQUIPPED", "USEITEM", "POINT", "SCENE"]),
        "item": HANDLE, "target": HANDLE, "position": POSITION, "right": field("boolean")}, ["action", "mode"]),
    ("observe", "Read entities within radius of the companion (default 20, maximum 32). Use nearby for plants and items for ground items. Use containers+contents for accessible storage, filter=icebox for fridges. Entity pages continue with offset=next_offset and the same filters. To continue a container's contents, use scope=containers, contents=true, container=its handle, contents_offset=its contents_next_offset. Limited data cannot prove absence. Terrain gives tiles/layout data.", {
        "scope": field("string", enum=["nearby", "inventory", "all", "structures", "creatures", "players", "containers", "items", "interactions", "terrain", "boats"]),
        "filter": field("string", "Substring of localized name or prefab, e.g. researchlab3 for Shadow Manipulator."),
        "radius": field("number", minimum=1, maximum=32), "contents": field("boolean"),
        "offset": field("integer", "Entity page offset from next_offset; keep other filters unchanged.", minimum=0, maximum=10000),
        "container": field("string", "Exact container handle, only with scope=containers.", maxLength=32),
        "contents_offset": field("integer", "Contents page offset from contents_next_offset; requires container and contents=true.", minimum=0, maximum=10000)}, []),
    ("get_capabilities", "Query native_commands coverage (composable/native_action_only/not_exposed; command IDs are not callable tools) and this character's callable role.actions, passive role.automatic, special role.recipes and equipment_slots. item_actions is a legacy subset; query_actions discovers native item uses. Never invent role abilities.", {}, []),
    ("character_skill", "Run an existing mod role action listed by get_capabilities.role.actions, reusing its original script. Supports Abigail modes/recall, role recipes/devices, bookshelf-aware reading, seasoning, lightning spear, Wortox heart operations and Wormwood carried medicine. Availability and original conservation/cost rules still apply. Does not grant every vanilla character a new skill.", {
        "ability": field("string", maxLength=80), "recipe": field("string", maxLength=80),
        "food": HANDLE, "spice": HANDLE}, ["ability"]),
    ("query_recipe", "Read live craft/cook recipes. Craft: native ingredient counts, deficits, source pickup/transfer instructions, tech and placement. Cook: count=pots; optional ingredients=four prefab IDs validates a hypothetical per-pot mix even before gathering. Returns mix, total deficits, sources, unavailable and stations. valid_mix is recipe validity, materials_ready is carried supply for all pots. Explicit fresh jerky is allowed only when the player requested it. Query outputs are estimates, never actual production.", {
        "query": field("string", maxLength=120), "kind": field("string", enum=["craft", "cook"]),
        "station": field("string", "Optional observed cooking-station handle; only used for kind=cook."), "count": COUNT, "ingredients": MIX}, ["query"]),
    ("move_to", "Travel to one known handle, land position, or named destination on this shard. Supports long land routes. Target a boat handle to board, or use shore to disembark at reachable nearby ground. Boarding requires a hoppable gap; this does not sail. Completion means actual arrival or boarding.", {
        "target": HANDLE, "position": POSITION, "destination": field("string", enum=["base", "speaker", "shore"]),
        "gait": field("string", enum=["walk", "run"]),
        "distance": field("number", minimum=.3, maximum=12)}, []),
    ("pickup", "Take a ground item or an accessible container slot item. Supply count for exact quantities; default one from a container, whole stack on the ground. For shared storage supply the physical opening as container. Automatically approaches/opens/closes and dismounts as needed. Ground backpacks are equipped and replace the old bag; check items and replaced_backpack. Heavy targets use the existing carry controller.", {
        "target": HANDLE, "count": COUNT, "container": HANDLE}, ["target"]),
    ("pickup_many", "Pick up multiple nearby ground stacks in one game-local job, then return total actual quantity/targets and failures once. Use for collecting drops such as living logs. One initial scan; newly spawned drops need another batch. Does not search containers or eat/equip unrelated items. Heavy objects require individual pickup, not this batch.", {
        "targets": field("array", "Optional observed handles; omit to scan matching ground items once.", items=HANDLE, maxItems=100),
        "filter": field("string", "Name/prefab substring; empty selects all eligible ground items.", maxLength=120),
        "radius": field("number", minimum=1, maximum=32)}, []),
    ("drop", "Drop carried or worn items, optionally at position. Returns item_state with the actual ground handle/location. Backpacks retain contents and are released from automatic recovery. Use to hand over the ORIGINAL worn bag before picking up a replacement.", {"item": HANDLE, "count": COUNT, "position": POSITION}, ["item"]),
    ("transfer", "Move carried storable items to a living player or accessible container, or from nested storage to snapshot.handle. Automatically approaches and opens/closes storage. Use revive for a ghost with a Telltale Heart; drop backpacks near the recipient. Check actual count/partial.", {"item": HANDLE, "destination": HANDLE, "count": COUNT}, ["item", "destination"]),
    ("equip", "Equip an owned item; does not re-equip an already equipped item.", {"item": HANDLE}, ["item"]),
    ("unequip", "Remove the exact slot from inventory.slot or get_capabilities.equipment_slots, including supported extra slots. Backpacks may drop to ground under native rules.", {"slot": field("string", maxLength=80)}, ["slot"]),
    ("craft", "Craft using carried materials. Automatically approaches a suitable nearby technology station when needed. For a building, auto prepares and places at an explicit position. mode=prepare spends materials at the station and keeps one native buffered build per recipe; mode=place uses it at the specified point without more materials or local tech. A blocked placement preserves a prepared build. Make multiple buildings at distinct points, one per call. Portable products go into inventory; deploy them separately.", {
        "recipe": field("string"), "count": COUNT, "position": POSITION, "station": HANDLE,
        "mode": field("string", enum=["auto", "prepare", "place"])}, ["recipe"]),
    ("work", "PICK/HARVEST once; CHOP/MINE/DIG/HAMMER until target finished unless amount specified. Use the observed work action and a carried tool. Carried raw materials must be dropped before working. Returns gained inventory counts, items and changed nearby ground_items; verify yields and pick up drops.", {
        "target": HANDLE, "action": field("string", enum=["CHOP", "MINE", "DIG", "HAMMER", "PICK", "HARVEST"]), "amount": COUNT}, ["target", "action"]),
    ("work_many", "Work multiple nearby matching resources in one game-local job: PICK/HARVEST once per target, CHOP/MINE/DIG/HAMMER until that resource is finished. Bring a proper tool. Returns aggregate actual progress and failures once; does not collect ground drops automatically.", {
        "targets": field("array", items=HANDLE, maxItems=100), "filter": field("string", maxLength=120),
        "radius": field("number", minimum=1, maximum=32),
        "action": field("string", enum=["CHOP", "MINE", "DIG", "HAMMER", "PICK", "HARVEST"])}, ["action"]),
    ("eat", "Eat one carried item under character diet and lethal-food guards; returns actual stat deltas.", {"item": HANDLE}, ["item"]),
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
