# Journey Together contributions

## Translation Pull Requests

Create `scripts/languages/<language code>/` and add the shared files:

- `command_words.lua`
- `dialogue_lines.lua`

Optional character-specific files use:

- `characters/<character>.lua`
- `characters/<character>_command_words.lua`

Copy `scripts/languages/_template` to begin. The Russian files under
`scripts/languages/ru/` are also a complete reference for Cyrillic keywords.
Keep existing command ids and
dialogue keys unchanged. Do not modify core code or `modinfo.lua`; the
maintainer handles review and release registration.

## Command keywords

The canonical file is `scripts/languages/<code>/command_words.lua`:

```lua
{ id = "existing_command_id", keywords = { "keyword" } },
```

Chinese keywords use substring matching. English and other Latin-script
keywords use word boundaries. The longest matching keyword wins; equal lengths
use the earlier entry. Only existing command ids are accepted.

## Character command files

Character command files use the same command entry format and are loaded from
`scripts/languages/<code>/characters/`. Keep command ids stable and provide a
localized `label` for the command wheel.

## Dialogue

The canonical file is `scripts/languages/<code>/dialogue_lines.lua`. Shared
lines use `lines`; fixed command responses use `replies`. Each file contains
one language only. Use `{1}` for a supplied name or argument.

## Branches

`main` is the stable release branch. `develop` is for integration and testing.
Feature branches should start from `develop`. Run the Lua syntax check and test
the affected language in a local DST world before submitting.
