# Journey Together

Journey Together is a Don't Starve Together companion mod. Companions can
follow players, assist in combat, survive independently, manage supplies, cook,
and respond to chat commands.

## Branches

- `main`: stable release branch.
- `develop`: integration and testing branch for the next version.
- `feature/*`: focused branches created from `develop`.

## Language files

Chinese is the default language. Keywords and dialogue are stored in two files
under `scripts/languages/<code>/` for each language.

Contributors only need to submit two files under
`scripts/languages/<code>/`:

- `command_words.lua`
- `dialogue_lines.lua`

They should not edit core code, pack manifests, or `modinfo.lua`. The maintainer
reviews and merges the language files, then adds the language option to
`modinfo.lua` before downloading the repository as a release mod. Missing files
fall back to Chinese.

The folder `scripts/languages/_template` is the starting point. Full formatting
rules are described in
[`CONTRIBUTING.en.md`](CONTRIBUTING.en.md).

## Local checks

Run the project's Lua 5.1 syntax check, then test the affected commands,
dialogue, language selection, and multiplayer chat display in a local DST
world.
