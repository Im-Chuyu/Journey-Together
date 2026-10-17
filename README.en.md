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

For Wigfrid, include her current name and `Elding Spear` to request spear crafting and charging. Keywords depend on the selected companion language. Chat and wheel commands share permission checks; character-specific commands require the corresponding character.

### Affinity and multiplayer permissions

Each player has an independent affinity score, normally starting at 20. Feeding, gifts and time spent together can increase affinity; attacking the companion reduces it.

- Following requires at least 25 affinity; work commands require strictly more than 50.
- Within the same priority tier, the latest valid follow request can replace the current leader. With A/B at 30/50, B can take over from A.
- Valid requests at 90 affinity or above have higher priority. Old requests do not indefinitely lock an independent companion after leadership ends.
- Taking items, renaming, changing characters and swapping bodies have their own distance, state and permission requirements.

The source also contains a designated-user exception that fixes that user's affinity at its maximum. See the [developer guide's permission rules](DEVELOPER.md#4-好感度领队与权限) for its location and details.

## Behaviour rules

| Area | Current behaviour |
| --- | --- |
| Setting a base | Uses the player's position when the command is issued as the centre, with a 32-unit radius. Records nearby cookpots, research stations, Salt Boxes, Ice Boxes, chests and other facilities without shifting the centre. Following remains active |
| Dodging | Uses enemy attack animations and danger windows to retreat or sidestep. A dangerous dodge can interrupt a normal attack before its damage frame; busy eating, revival and casting remain protected |
| Environmental escape | Prioritises leaving damaging areas before resuming combat, including cold or overheating caused by active temperature fields such as the Ice Crystaleyezer, using the actual coverage radius. Failed attempts try another direction; combat avoids remembered hazards. Detection is triggered by damage, without continuous global scans |
| Assistance marking | Each leader attack refreshes the target's assistance mark, which lasts for 16 seconds after the last attack. Existing combat safety and distance rules still apply |
| Disengaging to follow | While following normally, stops combat and catches up when more than 32 units from the leader. An accepted Follow command interrupts the current fight and pauses combat against its targets for 5 seconds, then resumes the existing combat assessment. Chat and wheel behave alike; environmental escape and busy actions remain protected |
| Combat equipment | Prioritises effective armour absorption against the current attack, then current temperature, rain and speed benefits, then durability. Multifunctional equipment remains eligible as armour. The Enlightened Crown is a combat fallback only when no usable head armour is available; its everyday preference is retained |
| Rain equipment | Counts combined equipment and inherent waterproofness. Once protection reaches 100%, extra rain-only items add no benefit; redundant worn items are stored under normal idle equipment rules. Multifunctional items needed for warmth or cooling remain equipped |
| Equipment maintenance | At 15% durability or below, uses carried materials for native sewing or forge repairs, including Eyebrellas, Thermal Stones, Voidcloth Umbrellas and other forge equipment. Nightmare-fuel equipment such as Bone Armor starts refuelling below 10% and stops above 90%. Missing materials prevent actions; unchanged inventory and durability do not trigger repeated checks |
| Facility and resource discovery | Reuses known locations and stops repeated searches after an empty result until relevant facilities, resources, inventory or search areas change. Shared notifications avoid adding listeners to every world entity, and caches allow removed objects to be collected while preserving search ranges and target ranking. Temporary caches are rebuilt after loading |
| Dropped weapons | Recovers the actual dropped item within 8 units, with deadlines and retry delays. Recovery stops if a player or another entity takes it |
| Companion resurrection | While ghosted, the chat or wheel Revive command seeks a usable haunt-based resurrection source within 16 units. Ghost/resurrection transitions retire old behaviour state; valid following or standby resumes after the native animation, including Wanda's Second Chance Watch resurrection |
| Plant Trees command | Plants an evenly spaced grid in a 20×20 square centred on the companion's position when ordered, using base forest spacing without a central aisle. Capacity follows side length and spacing; the current empty plot has 64 positions, and fewer carried seeds are planted until exhausted. Uses carried pine cones, birchnuts or twiggy tree cones. Does not clear land, chop trees, fetch chest supplies or relocate the base forest; normal work permissions apply |
| Engagement | Before displayed day 500, engages creatures hostile to the companion or nearby players. From day 500, the original combat assessment rules resume. If an enemy only targets a player and assistance is declined, the companion continues its current activity; escape only responds to personal threats. Brightshade bodies are only attacked while tired |
| Rescue | Following, waiting, base wandering and independent activity all allow rescuing players within 20 units, given suitable revival items or character abilities |
| Cooking | Only during independent base construction; disabled while following, at a manually assigned base and after construction finishes |
| Protected food | Does not eat Royal Jelly, Mandrakes or raw Tallbird Eggs. Never selects Deerclops Eyeballs or Guardian's Horns as food; manual feeding of these two items still follows native character diet rules |
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

Simplified and Traditional Chinese support custom companion voices; English and Russian use the character's native voice. Custom voice playback can be toggled in the Companion Voice setting.

## Development and contributions

- [DEVELOPER.md](DEVELOPER.md): architecture, behaviour rules, module index, extension steps, troubleshooting and test map, in Chinese.
- [AGENTS.md](AGENTS.md): concise maintenance constraints and entry points, in Chinese.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md) / [Chinese entry](CONTRIBUTING.md): translation submission rules.
- [Language directory guide](scripts/languages/README.md): file structure and templates.

`main` is the release branch; `develop` integrates the next version. Start new features from `develop`; maintenance agents use `codex/<topic>` branches by default. Sync `main` back into `develop` after a release, and use English commit and merge messages. Translation contributions must preserve command IDs, dialogue keys and placeholders, without changing core code, sound assets or release settings.

From the mod root, use Lua 5.1's `luac -p <file>` for syntax checks and `lua tests/<name>_test.lua` for relevant regressions. Full commands are in [section 18 of the developer guide](DEVELOPER.md#18-扩展步骤排错与验证). Changes affecting networking, saves or body swapping also need in-game verification beyond stub tests.

When reporting a problem, include the mod version, server type, relevant character, reproduction steps and the complete Lua traceback from the client or server log.
