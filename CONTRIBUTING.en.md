# Contributing

## Adding a language

Chinese is the default fallback. Create one folder and two files, for example:

- `scripts/languages/ja/command_words.lua`
- `scripts/languages/ja/dialogue_lines.lua`

Do not edit `modinfo.lua` in the translation pull request. The maintainer adds
`{description = "日本語", data = "ja"}` after review. Keep command ids and
dialogue keys unchanged.

Each dialogue line is a one element table such as `{ "A line" }`; each reply is
also a one element table. Do not put multiple languages in one entry.

## Adding keyword or dialogue packs

For optional aliases, create language-specific modules based on the templates
and add the base module name to the corresponding pack manifest. A keyword
entry uses an existing command id:

```lua
{ id = "follow", en = { "come along" } },
```

A dialogue pack uses the same keys already used by the companion:

```lua
return {
    lines = { greeting = { { "Hello there!" } } },
    replies = { follow_ok = { "All right." } },
}
```

Chinese keyword matching uses substrings. English and other Latin-script
keywords use word boundaries. The longest matching keyword wins; equal lengths
use the earlier entry.

## Branches

Use `main` for stable releases, `develop` for integration, and create focused
`feature/*` branches from `develop`.
