# Journey Together

Journey Together is a Don't Starve Together companion mod. Companions can follow players, assist in combat, survive independently, manage supplies, cook, and respond to chat commands.

## Branches

- `main`: stable release branch.
- `develop`: integration and testing branch for the next version.
- `feature/*`: focused branches created from `develop`.

## Command wheel

Press `Alt` plus the configured shortcut (default `Alt+R`) to open the companion command wheel. Right-click a wheel button to replace it from the complete command catalogue. The catalogue is paginated and duplicate commands are allowed. The shortcut can be changed to any `Alt+A`–`Alt+Z` combination in the `Command Wheel Shortcut` option in `modinfo.lua`.

Shared commands live in `scripts/languages/<code>/command_words.lua`. Character-specific commands live in `scripts/languages/<code>/characters/<character>_command_words.lua`, for example `characters/wickerbottom_command_words.lua`. Keep each command's stable `id` and provide localized `keywords` and a wheel `label`. The wheel combines shared and character-specific command files automatically, so adding a supported character command file adds it to the catalogue without changing the wheel widget.

Wigfrid command: include the companion’s current name and “Elding Spear” in chat, or use “Forge/charge Elding Spear” on the wheel. Following is not required. It crafts at most one spear from carried materials, then uses one Restrained Static to charge a carried or equipped spear, preferring the equipped one. An existing spear can be charged without crafting materials. It never gathers ingredients or takes them from chests. Charging an equipped spear requires one free slot and preserves skin, durability and cooldown.

## Companion food and combat

Companions cook only while independently building a base. Following a player, using a manually assigned home, or finishing base construction disables cooking. Royal jelly and mandrakes cannot be eaten or used as ingredients; raw Tallbird Eggs cannot be eaten. Jerky is reserved until its freshness falls below 50%. A pot cannot contain three or more fresh large meats, including cooked large meat; meat below 50% freshness is exempt from that restriction.

Wortox keeps 18 souls in inventory slots by depositing extras into carried Soul Jars and withdrawing souls when below 18. Full jars and unavailable inventory slots stop transfers. Souls are never transferred into backpacks. When hungry with more than 10 pocket souls, he eats souls first.

Wigfrid keeps her native meat-only diet and prefers jerky. When cooking is allowed, she prefers Meatballs. With an Elding Spear or Charged Elding Spear, she performs four normal attacks followed by one native lightning lunge. Below 10% durability she uses lunges only, resuming normal attacks above 20%. She avoids lunging at creatures with `sg.mem.burn_on_electrocute` that can burn, such as Treeguards, the Lord of the Fruit Flies, and Brightshades. Nearby saplings and crops do not block lunges. She waits for weapon cooldowns. Every five game days she asks her current leader for a spear or materials; a refusal within 30 seconds receives an acknowledgement.

Companions engage hounds and shadow creatures attacking themselves or nearby players. Brightshade bodies can only be attacked while tired; vines remain valid targets.

Before displayed world day 500, companions engage any creature hostile to themselves or nearby players without the ordinary creature-type, low-health or conservative fight-estimate restrictions. Neutral creatures and players are not automatically attacked. Brightshade reflection protection and dropped-weapon recovery remain active. The original combat rules resume on day 500.

Companions dodge on the server using enemy attack animations and danger frames. Retreat and side-step distances account for movement speed, terrain and boat boundaries. Attacking resumes after the danger window; unknown creatures or attacks use the generic dodge fallback.

Ordinary enemies such as Hounds and Treeguards also trigger dodge checks during attack windups. A companion completes the damage frame of its current attack, then can leave attack recovery to retreat. Frame monitoring reuses local query caches and avoids rescanning supplies or submitting the same path repeatedly.

After an accidental weapon or hand-tool drop, companions prioritize recovering the actual dropped item within 8 units and re-equip it after pickup. Backup tools do not overwrite the dropped-item record. Explicit player removal, another entity taking the item, broken equipment, or a full inventory will not cause repeated combat interruptions.

Weapons already auto-equipped by native pickup are not equipped a second time, preventing them from losing their inventory ownership. Each recovery attempt has a 10-second deadline including travel, followed by a 5-second retry delay after failure or a 1-second delay after interruption. Recovery uses the recorded dropped entity and performs no extra ground-weapon search.

After displayed world day 150 (starting on day 151), generic material stockpiling and reserve replenishment stop. Only 10 grass and 10 twigs are maintained at low priority. Rocks, gold and logs lose their generic reserve quotas; explicit work orders, ingredients for current crafting jobs and character-specific resources retain their own task rules.

Companions check for revivable players within 20 units while following, waiting, wandering at a base, or acting independently. Telltale Hearts, hauntable revival items, Wanda's revival watch, and Wortox's heart crafting can trigger rescue. Rescue outranks ordinary waiting and work commands, can temporarily leave the home activity boundary, and cancels if the player has already revived.

Only Wickerbottom uses bookcase memory. Assigning a new base scans once within 32 units of its center and saves shelf coordinates. Reading and storing use these records without periodically scanning the base. A read command with no shelf records performs one discovery scan, then ends if no shelf or requested book is found. Saved coordinates are checked by visiting them after loading; invalid records are removed. Memory persists separately per shard, and a new base replaces the old records.

## Dialogue and voice

Chinese is the default language. Simplified Chinese, Traditional Chinese, English, and Russian are currently included. Default dialogue lives in `scripts/languages/<code>/dialogue_lines.lua`; character-specific dialogue lives in `scripts/languages/<code>/characters/<character>.lua`. Missing character dialogue falls back to Wendy's default set.

The simplified-Chinese `voice_order` table assigns global voice event numbers in order. Each sound bank contains 70 events and is stored as `sound/fsN.fev` plus `sound/fsN.fsb`; event paths use the form `fsN/fsN/fnK`, with `K` continuing across banks. The `Companion Voice` option controls custom voice playback. Custom voice events are currently used only for Simplified Chinese and Traditional Chinese; other languages keep the companion character's native voice.

Language contributors only need to submit language files. They should not edit core code, sound banks, pack manifests, or `modinfo.lua`. The maintainer reviews language files and adds the language option to `modinfo.lua`. The `scripts/languages/_template` folder is the starting point; formatting and naming rules are described in [`CONTRIBUTING.en.md`](CONTRIBUTING.en.md). Missing language files fall back to Chinese.

## Local checks

Run the Lua 5.1 syntax check, then test the affected commands, dialogue, language selection, and multiplayer client display in a local DST world.
