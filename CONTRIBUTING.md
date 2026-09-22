# Journey Together contributions

## Translation Pull Requests

Create `scripts/languages/<language code>/` and add only:

- `command_words.lua`
- `dialogue_lines.lua`

Copy `scripts/languages/_template` to begin. Keep existing command ids and
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

## Dialogue

The canonical file is `scripts/languages/<code>/dialogue_lines.lua`. Shared
lines use `lines`; fixed command responses use `replies`. Each file contains
one language only. Use `{1}` for a supplied name or argument.

## Branches

`main` is the stable release branch. `develop` is for integration and testing.
Feature branches should start from `develop`. Run the Lua syntax check and test
the affected language in a local DST world before submitting.
