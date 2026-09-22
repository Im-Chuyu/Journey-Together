# Journey Together contributions

## Translation Pull Requests

Create a folder under `scripts/languages/<language code>/` and add only:

- `command_words.lua`
- `dialogue_lines.lua`

Copy `scripts/languages/_template` to begin. Keep existing command ids and
dialogue keys unchanged. Do not modify core code, pack manifests, or
`modinfo.lua`; the maintainer handles review and release registration.

## Command keywords

The canonical file is `scripts/languages/<code>/command_words.lua`.

Each language uses this shape:

```lua
{ id = "existing_command_id", keywords = { "keyword" } },
```

Keywords use substring matching in Chinese and word-boundary matching in
English. The longest matching keyword wins; equal lengths use the earlier
entry. Only existing command ids are accepted by a keyword pack.

## Dialogue

The canonical file is `scripts/languages/<code>/dialogue_lines.lua`. Shared
lines use the `lines` table and one-line command responses use `replies`.

Each language file contains only one language. Use `{1}` when the caller
supplies a name or other argument. Do not remove required keys from the Chinese
default file. Character-specific overrides use
`scripts/my_friend_dialogue_lines_<character prefab>_<language>.lua`.

## Branches

`main` is the stable, released mod branch. `develop` is for integration and
testing. Feature branches should start from `develop` and use a focused name,
for example `feature/dialogue-pack-wendy`.

Before submitting, run the Lua syntax check used by the project and test the
affected command or dialogue in a local DST world.
