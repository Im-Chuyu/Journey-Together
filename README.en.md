# Journey Together

Journey Together is a Don't Starve Together companion mod. Companions can follow players, assist in combat, survive independently, manage supplies, cook, and respond to chat commands.

## Branches

- `main`: stable release branch.
- `develop`: integration and testing branch for the next version.
- `feature/*`: focused branches created from `develop`.

## Command wheel

Press `Alt` plus the configured shortcut (default `Alt+R`) to open the companion command wheel. Right-click a wheel button to replace it from the complete command catalogue. The catalogue is paginated and duplicate commands are allowed. The shortcut can be changed to any `Alt+A`–`Alt+Z` combination in the `Command Wheel Shortcut` option in `modinfo.lua`.

Shared commands live in `scripts/languages/<code>/command_words.lua`. Character-specific commands live in `scripts/languages/<code>/characters/<character>_command_words.lua`, for example `characters/wickerbottom_command_words.lua`. Keep each command's stable `id` and provide localized `keywords` and a wheel `label`. The wheel combines shared and character-specific command files automatically, so adding a supported character command file adds it to the catalogue without changing the wheel widget.

## Dialogue and voice

Chinese is the default language. Simplified Chinese, Traditional Chinese, English, and Russian are currently included. Default dialogue lives in `scripts/languages/<code>/dialogue_lines.lua`; character-specific dialogue lives in `scripts/languages/<code>/characters/<character>.lua`. Missing character dialogue falls back to Wendy's default set.

The simplified-Chinese `voice_order` table assigns global voice event numbers in order. Each sound bank contains 70 events and is stored as `sound/fsN.fev` plus `sound/fsN.fsb`; event paths use the form `fsN/fsN/fnK`, with `K` continuing across banks. The `Companion Voice` option controls custom voice playback. Custom voice events are currently used only for Simplified Chinese and Traditional Chinese; other languages keep the companion character's native voice.

Language contributors only need to submit language files. They should not edit core code, sound banks, pack manifests, or `modinfo.lua`. The maintainer reviews language files and adds the language option to `modinfo.lua`. The `scripts/languages/_template` folder is the starting point; formatting and naming rules are described in [`CONTRIBUTING.en.md`](CONTRIBUTING.en.md). Missing language files fall back to Chinese.

## Local checks

Run the Lua 5.1 syntax check, then test the affected commands, dialogue, language selection, and multiplayer client display in a local DST world.
