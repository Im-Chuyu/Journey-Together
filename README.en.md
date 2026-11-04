# Journey Together · 一路同行

[简体中文](README.md) · [Developer guide (Chinese)](DEVELOPER.md) · [Contributing](CONTRIBUTING.en.md)

**Journey Together** is an AI companion mod for **Don't Starve Together**. Companions use real character entities, preserving native abilities, diet restrictions and equipment systems. Players interact through chat commands, a command wheel and an inventory panel.

A companion can follow and fight alongside players, or build a base, manage supplies and survive independently. Affinity is tracked per player, with multiplayer leadership and command permissions decided by the server.

## Features

| System | Capabilities |
| --- | --- |
| Interaction | Affinity, following and waiting, renaming, character and skin selection, body swapping |
| Work and bases | Gathering, chopping, mining, farming, sorting, carrying and independent base construction |
| Survival | Eating, cooking in supported states, lighting, temperature and rain equipment, supply replenishment |
| Combat and rescue | Combat assistance, attack-timed dodging, armour selection, dropped-weapon recovery and proactive player revival |
| Character abilities | Wortox soul management, Wickerbottom reading and bookcase memory, Wigfrid's Elding Spear behaviour and more |
| Multiplayer | Server-side AI, chat and wheel commands, inventory panel, shard travel and save restoration |
| Games | Gomoku and 19×19 Go against the companion, invited players or yourself, with saved results; a following companion sits nearby between higher-priority actions |
| Localization | Simplified Chinese, Traditional Chinese, English and Russian, with custom Chinese voice lines |

## Installation

The mod must be installed on **the server and every client**. It is not a client-only mod.

1. For a source installation, place the mod directory under the game's `mods/` folder, with `modmain.lua` and `modinfo.lua` directly inside that directory.
2. Enable Journey Together in the world's server mod list. Dedicated servers must enable it in the relevant shard configuration; clients should use the same version.
3. Configure the language, voice and shortcuts, then enter the world. The initial companion is Wendy, usually spawned near the Florid Postern or another world entrance. Existing companions are restored from saves.

The character catalogue includes native and loaded mod characters. Compatibility with individual mod characters and mods that change inventories, actions or state graphs needs separate verification.

## Getting started

### Controls

| Action | Default input |
| --- | --- |
| Open the command wheel | `Alt+R` |
| Customize a wheel slot | Right-click its button and choose from the paginated catalogue |
| Open the companion panel | `Alt+right-click` the companion |
| Issue a chat command | Include the companion's current name and a command keyword in the same message |

The wheel shortcut can be set to any `Alt+A`–`Alt+Z` combination. The wheel and panel also support optional F1–F12 shortcuts and buttons at the top of the screen.

For a companion currently named “Wendy”, English command examples include:

- `Wendy, follow me`: request following.
- `Wendy, stay here`: hold position.
- `Wendy, this is home`: assign a base.
- `Wendy, chop`: request work, subject to permissions and tool requirements.
- `Wendy, plant trees`: plant carried tree seeds in a square extending 10 units along each axis from the companion's position when ordered.
- `Wendy, portal respawn`: send a ghost companion to a portal to revive. A destination (`gate`, `florid postern` or `portal`) and a revival keyword (`revive`, `resurrect`, `come back to life` or `respawn`) must both occur. Without a destination, revival commands use the same nearby search within 16 units as the wheel's Revive action.

For Wigfrid, include her current name and `Elding Spear` to request spear crafting and charging. Keywords depend on the selected companion language. Chat and wheel commands share permission checks; character-specific commands require the corresponding character.

### Affinity and multiplayer permissions

Each player has an independent affinity score, normally starting at 20. Feeding, gifts and time spent together can increase affinity; attacking the companion reduces it.

- Following requires at least 25 affinity; work commands require strictly more than 50.
- Within the same priority tier, the latest valid follow request can replace the current leader. With A/B at 30/50, B can take over from A.
- Valid requests at 90 affinity or above have higher priority. Old requests do not indefinitely lock an independent companion after leadership ends.
- Taking items, renaming, changing characters and swapping bodies have their own distance, state and permission requirements.

The source also contains a designated-user exception that fixes that user's affinity at its maximum. See the [developer guide's permission rules](DEVELOPER.md#4-好感度领队与权限) for its location and details.

When the companion asks a question, reply directly without its name: “crack them” / “keep them” for rock fruit, “eat it” / “no” for Jellybeans, or “yes” for pickup permission. These replies apply only to the pending question and are absent from the command wheel. Approved rock fruit is dropped as a stack and mined with consecutive swings; safety and higher-priority behaviour can still interrupt.

## Behaviour rules

While the companion is fighting, send its name followed by encouragement in chat, such as “Wendy you can do it” or “Wendy keep it up”. It replies with a random supportive line without interrupting combat, requiring following or spending affinity. Replies have a six-second cooldown. Carried armour is also equipped when unarmed or holding only a weak tool.

The **Games** button sits inside the bottom-right corner of the companion info strip and requires at least 20 affinity. Choose Gomoku, Go or Chinese Chess, then the companion or a player from the current world's online list (same shard). Selecting yourself starts immediately. Seats are assigned randomly; Black moves first in Gomoku/Go and Red in Chinese Chess. Invitees click the notification below the companion HUD buttons, then accept or decline; invitations expire after 45 seconds.

Attacks and death do not close the board. Minimize retains the game; Leave Game ends it after confirmation. Request Black (Red for Chinese Chess) asks the opponent to restart with you moving first; the companion agrees automatically, and requests expire after 30 seconds. Names have current character-skin head portraits. Private chat shows five messages with vertical scrolling through the latest 40, supports quick phrases and the game's complete registered emoji catalog, and never posts to public chat. Companions add casual dialogue and a random line for the player's win or loss; in player-versus-player games they root only for the player they currently follow. All game labels, tasks and dialogue support Simplified Chinese, Traditional Chinese, English and Russian.

The world continues running; active boards are not restored. Disconnecting, changing shards or removing a player body ends the match. **Match history** at the top-left of the board lists all saved results in this world shard, including both names, win/loss/draw/interruption and game type. Results survive restarts in paginated storage; boards and chats are not archived. History is independent of world snapshots, so rolling back does not roll back saved results. Forest and caves have separate archives, and earlier unrecorded games cannot be recovered. All board panels hide the board title and include a takeback button.

Chinese Chess uses a 9×10 board with Red moving first. Select a piece, then its destination; Black views a rotated board. Checkmate and stalemate lose. Takebacks, draw offers and requests to play Red share the existing game controls. Threefold repetition uses simplified adjudication: a perpetual checker loses, otherwise draw; full tournament chase adjudication is not implemented. The game draws after 120 plies without capture or forward soldier movement, or 1024 total plies.

Gomoku uses a 15×15 board with five or more in a row winning. Go uses 19×19, area scoring, 7.5 komi for White, no suicide and positional superko. Two consecutive passes or an accepted Count request starts scoring. Click stones to toggle whole dead groups; changes clear both confirmations. Both sides confirm to finish, or either can resume play if they disagree. Draw offers need the opponent's approval. Offers expire after 30 seconds and become invalid when play changes. Self-play confirms once per side. A companion game accepts takebacks immediately and rolls back the player's latest move together with the companion reply; player-versus-player games require the opponent to approve a 30-second takeback request. The companion uses a lightweight tactical search: it accepts count/draw requests and the player's dead-group choices, without automatic complex life-and-death adjudication. Empty regions bordering both colours are neutral.

Chat retains five visible rows with tighter spacing and full-message hover text, leaving more space for the board. The Go companion compares a move, the opponent's reply and its own continuation, balancing captures, group safety, eyes and local influence. It no longer automatically passes after an early player pass. Chinese Chess uses bounded iterative search with capture exchanges and check evasions. Both searches run in short slices, cap temporary caches and release search data after the turn. Entertainment adds no periodic world scans or synchronization polling. Requests trigger validation, targeted updates and history IO; bot turns and invitation expiry use one-shot tasks. A companion only approaches and loops `/sit` while following its game opponent; survival, combat and work can interrupt it, after which it returns to sit nearby.

| Area | Current behaviour |
| --- | --- |
| Multiplayer assistance | Helps only the current leader; fights involving other players do not trigger assistance. Without a leader, combat follows the companion's own threats and combat rules |
| Boat following | Pursues the leader's current position using native reachable hops, without replaying obsolete boarding trips. After boarding, first moves up to 4 units toward the player on deck before resuming disembark following; blocked moves time out. Landing restores ground routes, and a fresh Follow command clears failed routes. There is no separate periodic platform observer |
| Setting a base | Uses the player's position when the command is issued as the centre, with a 32-unit radius. Records nearby cookpots, research stations, Salt Boxes, Ice Boxes, chests and other facilities without shifting the centre. Following remains active |
| Dodging | Uses enemy attack animations and danger windows to retreat or sidestep. A dangerous dodge can interrupt a normal attack before its damage frame; busy eating, revival and casting remain protected |
| Environmental escape | Prioritises leaving damaging areas before resuming combat. For the Ice Crystaleyezer, avoids the inner ground-ice circle (native radius 3.5), which directly lowers body temperature, without excluding the whole outer cooling field (radius 35), where heating can offset the cold. Other active temperature sources retain their danger radii. Failed attempts try another direction; combat avoids remembered hazards. Detection is triggered by damage, without continuous global scans |
| Assistance marking | Each leader attack refreshes the target's assistance mark, which lasts for 16 seconds after the last attack. Existing combat safety and distance rules still apply |
| Disengaging to follow | While following normally, stops combat and catches up when more than 32 units from the leader. An accepted Follow command interrupts the current fight and pauses combat against its targets for 5 seconds, then resumes the existing combat assessment. Chat and wheel behave alike; environmental escape and busy actions remain protected |
| Weather dialogue | Near its current leader, speaks once when rain or snow starts, with no weather dialogue cooldown or rain-gear requirement. Stopping and restarting precipitation triggers another line; continuous precipitation does not repeat it. Snow reuses the winter dialogue pool |
| Voice queue | Chinese custom voice clips play in trigger order using their recorded durations. Once a short clip finishes, the next can start without a fixed 7-second wait. Unknown durations use a 7-second fallback. Text appears immediately. Death, becoming a ghost or removal clears the queue |
| Combat equipment | Prioritises effective armour absorption against the current attack, then current temperature, rain and speed benefits, then durability. Multifunctional equipment remains eligible as armour. The Enlightened Crown is a combat fallback only when no usable head armour is available; its everyday preference is retained |
| Retreating without equipment | Below 80% health, stops fighting and moves away if it has no usable armour and every available hand item deals less than 25 damage. Early-world engagement and assistance do not bypass this rule. Carried, backpack and worn equipment all count |
| Base equipment | While idle inside a player-assigned base, fills missing weapon or armour roles using carried supplies and accessible chests or ground materials inside the base. Tries a Football Helmet and Ham Bat first, then a Log Suit and Spear; if neither set is affordable, still crafts an affordable single item. Can refine Rope. Keeps existing gear and retries after 4 minutes if nothing can be made. Native research requirements still apply; survival, combat and explicit commands take priority |
| Rain equipment | Counts the best usable item per slot plus inherent waterproofness, without adding spare items from the same slot. Inside a player-assigned base, crafts an Umbrella when available protection is below 80%; a Football Helmet's 20% does not prevent crafting, while exactly 80% does. Rain and combat preparation share the same priority and have independent 4-minute failure retries. Once worn protection reaches 100%, extra rain-only items add no benefit; redundant worn items are stored under normal idle equipment rules. Multifunctional items needed for warmth or cooling remain equipped |
| Sewing supplies | Inside a player-assigned base, crafts one Sewing Kit if no usable sewing supply is carried. An existing usable kit or Sewing Tape prevents duplicates. Uses native research and container permissions, shares equipment preparation priority, and has an independent 4-minute failure retry. Survival, combat, rescue and explicit commands take precedence |
| Equipment maintenance | At 15% durability or below, uses carried materials for native sewing or forge repairs, including Eyebrellas, Thermal Stones, Voidcloth Umbrellas and other forge equipment. Nightmare-fuel equipment such as Bone Armor starts refuelling below 10% and stops above 90%. Missing materials prevent actions; unchanged inventory and durability do not trigger repeated checks |
| Facility and resource discovery | Reuses known locations and stops repeated searches after an empty result until relevant facilities, resources, inventory or search areas change. Shared notifications avoid adding listeners to every world entity, and caches allow removed objects to be collected while preserving search ranges and target ranking. Temporary caches are rebuilt after loading |
| Dropped weapons | Recovers the actual dropped item within 8 units, with deadlines and retry delays. Recovery stops if a player or another entity takes it |
| Companion resurrection | While ghosted, the chat or wheel Revive command seeks a usable haunt-based resurrection source within 16 units. Ghost/resurrection transitions retire old behaviour state; valid following or standby resumes after the native animation, including Wanda's Second Chance Watch resurrection |
| Plant Trees command | Plants an evenly spaced grid in a 20×20 square centred on the companion's position when ordered, using base forest spacing without a central aisle. Capacity follows side length and spacing; the current empty plot has 64 positions, and fewer carried seeds are planted until exhausted. Uses carried pine cones, birchnuts or twiggy tree cones. Does not clear land, chop trees, fetch chest supplies or relocate the base forest; normal work permissions apply |
| Engagement | Before displayed day 500, engages creatures hostile to the companion or nearby players. From day 500, the original combat assessment rules resume. If an enemy only targets a player and assistance is declined, the companion continues its current activity; escape only responds to personal threats. Brightshade bodies are only attacked while tired |
| Rescue | Following, waiting, base wandering and independent activity all allow rescuing players within 20 units, given suitable revival items or character abilities |
| Cooking | Available across activity modes. Roasts ingredients that cost health or have less than 20% freshness; sanity cost alone does not trigger roasting. Crock-pot meals can use ingredients from accessible Ice Boxes, Salt Boxes and chests |
| Recipe choice | Uses current three-stat deficits: low health favours healing meals, low sanity favours sanity recovery, low hunger favours high-hunger meals, and full stats favour high-calorie meals. This prevents a fixed preference for meat stew |
| Jellybeans | Jellybeans (`jellybean`, not Taffy) are excluded from ordinary autonomous eating. Below 20% health with insufficient healing food, the companion makes one nearby/inventory/container/ground search, asks the following player, and eats at most one piece after approval. The scan cools down for 4 minutes |
| Protected food | Autonomous eating checks current health both when choosing food and immediately before consumption, rejecting a predicted lethal serving from inventory or containers. Does not eat Royal Jelly, Mandrakes or raw Tallbird Eggs. Never selects Deerclops Eyeballs or Guardian's Horns as food; manual feeding of these two items still follows native character diet rules |
| Charcoal and Ashes | Carried as materials and excluded from companion eating or manual feeding. Giving or taking them does not trigger food dialogue; gifts do not earn food-gift affinity |
| Pot ingredients | Honeycomb (`honeycomb`), Royal Jelly and Mandrakes never enter a crock pot. Jerky at 50% freshness or above is reserved; fresh large meat is limited to two portions, while a third portion is allowed only when its freshness is below 20% |
| Ordinary healing | Wanda and characters with an age component, age-based health tag or native healing-disable markers are excluded from soul and food healing targets. Feeding for hunger remains available |
| Ingredients | Royal Jelly and Mandrakes cannot enter a pot. Jerky at 50% freshness or above is reserved; combinations of three or more large meats are subject to freshness restrictions |
| Late-world supplies | From displayed day 151, generic stockpiling stops; only 10 grass and 10 twigs are maintained at low priority. Explicit tasks and character-specific resources keep separate rules |

Dodging depends on enemy timing, traversable terrain and the companion's current state; it does not guarantee avoiding every hit. Detailed thresholds, exceptions and module responsibilities are documented in the [developer guide](DEVELOPER.md).

### Character-specific examples

- **Wortox** balances pocket souls with carried Soul Jars, aiming for 18 pocket souls and never transferring souls into backpacks. When hungry with more than 10 pocket souls, he eats souls first.
- **Wortox player healing** responds to health changes within 10 units and checks the same area every 30 seconds as a fallback. Below 80% health, he approaches and drops one soul at a time, stopping at 80%. Target discovery does not repeatedly poll every player's health.
- **Wickerbottom** remembers bookcase coordinates when a base is assigned, allowing reading and storage trips to distant recorded shelves. Each read request can refresh the base once if no usable book is found. Outside the base, or if the book is still unavailable, she searches once within 20 units of her current position. Shelves outside the base are remembered only for that request and are not saved. There are no periodic discovery scans.
- **Wigfrid** retains her meat-only diet and prefers Jerky. With an Elding Spear, she performs four normal attacks followed by a lightning lunge. Low durability switches her to lunges only; she avoids lunging at creatures that would ignite from electrocution.
- **Wanda and Wortox** can use their character-specific revival abilities when suitable items or materials are available.

Wigfrid's Elding Spear command crafts at most one spear from carried materials, then tries to charge a carried or equipped uncharged spear with one Restrained Static, preferring the equipped weapon. An existing spear can be charged without crafting first. The command does not gather ingredients or take chest supplies. Charging an equipped spear requires one free slot. Every five game days, she asks her current leader for a spear or materials only if she carries neither a normal nor a charged Elding Spear, and acknowledges a refusal within 30 seconds. Receiving a spear suppresses further requests and clears any pending question.

## Language and voice

Choose Simplified Chinese, Traditional Chinese, English or Russian in the mod settings. The initial choice follows the game locale, defaulting to English for unmatched locales. Missing language resources have a Chinese fallback.

Simplified and Traditional Chinese support custom companion voices; English and Russian use the character's native voice. Disabling Companion Voice also skips registering the custom FMOD banks, which reduces audio memory pressure alongside large audio mods.

## Local voice and body interface (foundation)

For direct DeepSeek API access, fill `api_key` in the mod-root `AssistantAPI.json` and double-click `StartVoice.vbs`. The file is generated on first launch, or copy `AssistantAPI.example.json` and rename it. With the default `provider=auto`, a configured key selects API mode without a browser or extension. Default model: `deepseek-flash`; proactive API chat is off by default. Enable AI Model Mode in game and match the pairing code. Restart after editing. Uses the Python standard library; API usage is billed to the key owner. The Workshop exporter generates blank configurations instead of copying local credentials. Mocked API tests pass; a real paid API and in-game end-to-end run have not been performed. See [assistant settings](tools/companion_bridge/README.md).

Double-click `StartVoice.cmd` in the mod root on your own Windows PC. With no API key configured, it uses the web bridge for DeepSeek and Doubao: load the bundled `browser_extension` in Chrome/Edge, sign in yourself, and pair its dedicated chat tab using the assistant's web connection code. A player verified basic inventory chat through real Chrome on 2026-11-02, including the in-game reply; complex automated actions and long-running background stability still need verification. `--provider demo` selects the separate offline demonstration; web mode never silently falls back to it.

Enable AI Model Mode in mod configuration (off by default). The six-digit code defaults to 321151; customize its six digit selectors and match the assistant's Settings. Neither following nor initial proximity is required to connect. Failed attempts wait 5,10,15… seconds and stop after 30 failures; entering a new world resets the budget. Disabling this mode disables model interfaces, behaviour nodes and connection tasks; enabling it always connects automatically. Pairing preferences persist across assistant restarts, and the extension automatically reconnects reopened DeepSeek pages using the saved code, retaining the original tab while it remains available. Manual console pairing remains available; stop disables retries for the current world.

While connected, all players can address the companion by name in public game chat; server relays also support surface/cave messages. One room assistant is enough. Assistant text and voice address the companion directly and do not require the name. Everyone can chat; while following, only the leader can assign work; while independent, anyone can assign basic work. Bystander chat queues behind an active model plan. Disconnection restores the original chat handling. Cross-shard speakers have no local entity handle: following, delivering to them and role commands requiring a local player need the same shard.

`pickup_many` and `work_many` complete a bounded batch locally before returning an aggregate result. `craft(count)` already finishes the entire requested number of operations in the game.

Game commands and new model requests can replace each other at safe animation boundaries, preserving emergency priorities and the connection. Character-specific voice guidance follows the actual character. Random 60–120 second environment updates may invite a short proactive chat while idle; these turns cannot issue physical commands. The speech hotkey defaults to F9 and can be changed to F1–F12 in Settings. An explicit continuous-listening button keeps the microphone active until stopped. Real remote-client and background-site stability still need multiplayer/browser verification.

Python and models are not bundled. On 64-bit Windows, StartVoice.vbs reuses Python 3.10+ with Tkinter or downloads and installs it on first launch. Offline speech is prepared separately in assistant settings; Windows speech requires an installed recognizer. New runtime files and settings live in tools/companion_bridge/.local. `model_instructions.md` teaches the model the 35 skills and actual-feedback planning. Follow uses the original background mode; work needs no follow cancellation, and idle life resumes normally. `interact` supports advertised sitting, switch and activation components, not arbitrary custom mod actions. Background page heartbeats have a 120-second grace period; bounded diagnostics omit transcripts and pairing secrets. Reload server/client Lua, the assistant, and the browser extension after updating. See [BODY_API.md](BODY_API.md) for details (Chinese).

The model also supports world saves, rollback counts, server pause/resume and admin grants/revocation. Saving is available to connected users; rollback and pause require server admin status or an admin grant. Only admins can grant access. Grants persist by userid in world snapshots; the master shard authorizes cave requests.

For combat, engage directly targets an observed creature and continuously tracks, approaches and attacks it; no preliminary move_to is required. Dodge, survival, equipment and follow-distance rules still apply.

The model can query current recipe costs/deficits and role capabilities, harvest a ready pot and preserve inventory intent across multi-step tasks. Role calls bridge only the eight existing scripted characters; capabilities distinguish active commands from automatic/passive support. See BODY_API.md.

## Development and contributions

- [DEVELOPER.md](DEVELOPER.md): architecture, behaviour rules, module index, extension steps, troubleshooting and test map, in Chinese.
- [AGENTS.md](AGENTS.md): concise maintenance constraints and entry points, in Chinese.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md) / [Chinese entry](CONTRIBUTING.md): translation submission rules.
- [Language directory guide](scripts/languages/README.md): file structure and templates.

`main` is the release branch; `develop` integrates the next version. Start new features from `develop`; maintenance agents use `codex/<topic>` branches by default. Sync `main` back into `develop` after a release, and use English commit and merge messages. Translation contributions must preserve command IDs, dialogue keys and placeholders, without changing core code, sound assets or release settings.

From the mod root, run Lua 5.1's `luac -p <file>` on the affected files and the relevant regression tests; small changes do not require the full suite. Section 18 of the developer guide describes the scope-based checks and the full commands. Changes affecting networking, saves or body swapping also need in-game verification beyond stub tests.

When reporting a problem, include the mod version, server type, relevant character, reproduction steps and the complete Lua traceback from the client or server log.

The web extension now supports DeepSeek and Doubao. Choose a site from the desktop’s Open Model Page menu and pair that tab. Optional automatic conversation renewal triggers only on a visible context-limit notice, never after a fixed number of messages; it resends the current pending request with its complete state and actual results. Reload the extension, allow the added Doubao hosts, refresh the chat page and restart the assistant after updating. Doubao live integration remains unverified; DOM tests cover its adapter and renewal workflow.

Native query_actions/perform_action now bridge inventory/equipped, target/ground and scene interactions. Single-target work defaults to completion. Only public game chat requires the companion name. World save/rollback/pause and new kick/ban actions use mandatory two-message reason review by the model, replacing administrator grants.

Generic query_batch and execute_sequence now combine independent observations and execute decided steps locally. First failure returns actual progress for standalone fallback without replaying completed actions. Native planting/deployment/terraforming remain subject to game rules; drop accepts a destination position. Restart the assistant and world to load this update.


AI planning now combines carried deficits, ground and accessible-container supplies, suitable technology stations and building-site candidates in one recipe query. `query_sites` also supports carried deployable items. Buildings require explicit, distinct locations; failed sequences resume from unfinished work. Tool crafting and the location of its later use are separate decisions. Restart the assistant, reload the extension and refresh the model tab after updating. The new conversation and Doubao composer adapters still require live website and game validation.

Model-driven container pickup and deposit now approach, open, transfer and close automatically within one request. Cancellation or disconnection closes only containers opened by that job; the leader’s existing openings are preserved. Re-enter the world to load the Lua changes.

Model tools now expose terrain, soil and care targets, container capacity and fuel state, with fixed grid layouts and bounded repeated sequences. Cooking can return after starting; non-stacking storage reports actual progress. Instructions are shorter and cover abbreviations, ratios and recovery. Restart the assistant and re-enter the world; new complex workflows still require in-game validation.

Recipe queries now distinguish owned supplies from native crafting availability and report deficits, technology and role conditions. Failure feedback preserves progress. World-operation reason requests and expired reviews end the current turn to prevent repeated submissions. Restart the assistant and re-enter the world after updating.

Speech-only model replies now end the turn. A response containing both text and say is spoken once, preventing completion-message loops. Restart the assistant to apply this fix.

Ambient prompts now explicitly request brief conversation based on current companion/world/surroundings data. Empty ambient replies no longer fill dialogue history. Restart the assistant; existing cooldown and safety rules remain.

Use StartVoice.vbs for a windowless-console launch. Assistant settings now offer local Whisper recognition (initial dependency/model download required), installed TTS voice/rate/volume selection with preview. Windows recognition remains available. Exit the old assistant normally before using the new launcher.

If Python needs to be installed, the launcher tries python.org, then the Alibaba Cloud and Huawei Cloud mirrors. It verifies the same pinned SHA-256 for every download before running the installer.

Model pickup now delegates a selected heavy object to the existing carry controller and can compose movement and dropping. It preserves native backpack/mount handling and never silently substitutes another object. Capability queries report built-in command coverage; some persistent behaviors still require native commands. Re-enter the world and restart the assistant.

Reply extraction now handles split request IDs and deeply nested message text, with clearer timeout diagnostics. Reload the extension, refresh the model page and restart the assistant. Old actions are not replayed.


Model task planning now retains bounded per-task object bindings and remaining steps. Observations distinguish wearable bags from storable items and expose harvest products and ingredient tags. Cooking can validate and preserve an explicit four-slot mix with batch deficits. Restart the assistant and world, reload the browser extension, and refresh the model page. Live model task reliability still requires in-game testing.


Use the assistant’s “大模型设置” (Model settings) button, also available inside Assistant settings, to edit the API model, thinking mode and effort (low/high/max), output limit, timeout, retries and proactive chat. Changes are validated and saved to AssistantAPI.json; restart the assistant to apply them.


Model observations now include current-base membership, ground tiles and topology-backed region information. Large container queries retain object identities before contents and expose pagination for focused follow-up scans. Restart the assistant and re-enter the world to load the changes; live-world verification remains pending.

The model also receives the companion's world type (surface or caves) and shard ID, independently of the speaker's location. Restart the assistant and game session after updating.

The companion can prepare a building at a technology station and place it elsewhere, travel to a known base on the same shard, board a nearby boat or hop ashore, dismount to swap backpacks, sit on the ground, use shared shadow storage, and revive ghosts with a Telltale Heart. It can start two pots before harvesting either. See [BODY_API.md](BODY_API.md) for the tool parameters and examples.

On a Linux dedicated server, configure the DeepSeek API key in `AssistantAPI.json` and run `sh ./StartAssistantLinux.sh` with Python 3.10 or newer. Enable AI Model Mode and match the six-digit pairing code. The companion's shard pairs automatically when the companion and an online player are present. A code mismatch stops automatic retries.
