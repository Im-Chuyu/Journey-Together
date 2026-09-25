# Contributing

## Translation Pull Requests

Create `scripts/languages/<language code>/` and add the shared files:

- `command_words.lua`
- `dialogue_lines.lua`

Optional character-specific files use:

- `characters/<character>.lua`
- `characters/<character>_command_words.lua`

Copy `scripts/languages/_template` to begin. The Russian files under
`scripts/languages/ru/` are also a complete reference for Cyrillic keywords.
Do not edit core code or
`modinfo.lua` in a translation pull request. The maintainer reviews the files,
registers the language, and publishes the next mod version.

## Keyword entries

Use an existing command id:

```lua
{ id = "follow", keywords = { "come along" } },
```

Character command files use the same entry format and are loaded from
`scripts/languages/<code>/characters/`. Keep command ids stable and provide a
localized `label` for the command wheel.

## Dialogue entries

Use existing dialogue keys:

```lua
return {
    lines = { greeting = { { "Hello there!" } } },
    replies = { follow_ok = { "All right." } },
}
```

Each file contains one language only. Keep command ids and dialogue keys
unchanged. The longest matching keyword wins; equal lengths use the earlier
entry.

## Branches

Use `main` for stable releases, `develop` for integration, and focused
`feature/*` branches from `develop`. Run the Lua syntax check and test the
affected language in a local DST world before submitting.
