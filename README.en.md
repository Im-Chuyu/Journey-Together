# Journey Together

Journey Together is a Don't Starve Together companion mod. Companions can
follow players, assist in combat, survive independently, manage supplies, cook,
and respond to chat commands.

## Branches

- `main`: stable release branch.
- `develop`: integration and testing branch for the next version.
- `feature/*`: focused branches created from `develop`.

## Language files

Chinese is the default language. Keywords and dialogue are stored in separate
files for each language:

- `scripts/my_friend_command_words_zh.lua`
- `scripts/my_friend_command_words_en.lua`
- `scripts/my_friend_dialogue_lines_zh.lua`
- `scripts/my_friend_dialogue_lines_en.lua`

To add another language, copy the corresponding templates, use the same
command ids and dialogue keys, and add the language to `configuration_options`
in `modinfo.lua`. For example, a language code `ja` loads
`my_friend_command_words_ja.lua` and `my_friend_dialogue_lines_ja.lua`.
Missing dialogue or keywords fall back to Chinese.

Optional contributor packs are registered in
`scripts/my_friend_command_word_packs.lua` and
`scripts/my_friend_dialogue_packs.lua`. Full formatting rules are described in
[`CONTRIBUTING.en.md`](CONTRIBUTING.en.md).

## Local checks

Run the project's Lua 5.1 syntax check, then test the affected commands,
dialogue, language selection, and multiplayer chat display in a local DST
world.
