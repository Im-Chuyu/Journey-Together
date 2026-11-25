# Contributing to Journey Together

[简体中文](../../CONTRIBUTING.md) · [Translation reference](../../scripts/languages/README.md)

## Report an issue

Include the mod version, the character involved, whether the host was a player or a dedicated server, and whether you were in the forest or caves. Describe what you did, what you expected and what happened. For a Lua error, include the first error and its full stack trace. Remove personal information before sharing a log excerpt. [Issue tracker](https://github.com/Im-Chuyu/Journey-Together/issues)

## Translate the mod

1. Branch from `develop`. Edit the existing language folder, or copy the [template](../../scripts/languages/_template) to `scripts/languages/<code>/`. The [English](../../scripts/languages/en) and [Russian](../../scripts/languages/ru) folders include complete examples.
2. Use `command_words.lua` for command keywords, `dialogue_lines.lua` for conversations and `games.lua` for board game text. Character-specific dialogue and wheel entries belong under `characters/` in the same language directory.
3. Keep command IDs, dialogue keys, voice numbers and placeholders such as `{1}` and `%s`. When keywords overlap, the longest match wins. Equal-length matches use their original order. The maintainer registers new languages in the mod settings.
4. Open a pull request against `develop`. Include the language, changed files, and the keywords or screens you checked. Keep translation changes within the relevant language folder.

## Code and documentation

Start from `develop`, the integration branch. Public versions live on `main`. Use an English commit and merge description. State what changed and how you checked it. Lua files use Lua 5.1, UTF-8 and four-space indentation.

Player controls belong in the [player guide](player-guide.md). The [developer reference](../DEVELOPER.md) describes system behaviour and module boundaries, and the [action API](../BODY_API.md) documents tool parameters. Keep personal assistant settings, keys, saves and the local test directory out of commits.
