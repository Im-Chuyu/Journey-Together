# Language submissions

This directory is the translation area of the project. A language submission
can add shared files and optional character-specific files:

```text
scripts/languages/<code>/command_words.lua
scripts/languages/<code>/dialogue_lines.lua
scripts/languages/<code>/games.lua
scripts/languages/<code>/characters/<character>.lua
scripts/languages/<code>/characters/<character>_command_words.lua
```

Use `zh`, `en`, and `ru` as references. Keep command `id` values and dialogue
keys unchanged. A language file contains only one language. Chinese is the
fallback when a file is missing.

The shared `revive` command may provide `portal_keywords`, a separate list of
destination words such as `gate` or `portal`. A named ghost companion goes to
a portal only when both a destination and a revival keyword occur in the chat
message. Revival keywords without a destination use nearby resurrection,
just like the wheel. Keep these word groups separate and preserve the `revive`
ID; do not replace them with fixed phrases such as `portal respawn`.

For Chinese voice lines, both `zh/dialogue_lines.lua` and
`zh_tw/dialogue_lines.lua` contain their own `voice_order` table. The two
tables must keep the same `fn_number` for matching lines because the audio
catalogue is shared, while their text remains independent. The legacy
`voice_order = {{"key", line_index}}` format is supported; new entries should
use `{"key", line_index, fn_number}` to bind a line to a permanent audio
number. The `fn_number` is global across all sound banks, must never be reused,
and should be increased when a new audio file is added. Changing the text of
an existing line does not require changing its voice number.

Shared dialogue files use the same order: chat keywords/replies, all numbered
text in ascending fn order, unnumbered text, then `M.voice_order` for Chinese
locales. Dialogue and replies are assigned as `M.lines.<key>` and
`M.replies.<key>` groups in that shared numeric sequence, rather than separate
sections that scatter high fn numbers among older text. Keep one variant per
line with its `-- fnN` comment at the end; a single-variant group may fit on one
line. Place new numbered text after the current highest fn, before unvoiced text.
Voice bindings remain explicit and in their original order, grouped by bank
with at most three entries per line. English/Russian fn comments are references
to Chinese audio slots and do not enable custom voice playback.
The shared catalog currently assigns every spoken line a slot through fn695.
Slots fn663–fn669 cover tree-planting and Abigail command replies in fs10;
fn670–fn692 cover the time-rewind, rain and seasonal contextual lines;
fn693–fn695 cover the follow-again reunion lines.
Simplified and Traditional Chinese use identical keys, indices and numbers.

Character command files use stable command `id` values plus localized
`keywords` and a wheel `label`. Contributors should submit these files through
a pull request. Do not edit
`modmain.lua`, AI behavior files, or the language loader for a translation.
The maintainer reviews and merges the files, then adds the language option to
`modinfo.lua` before releasing it in the mod.

`games.lua` contains board-game UI labels and server error reasons. Preserve
all keys and `%s` formatting placeholders. Missing translations fall back to
Chinese. Game identifiers such as `gomoku` remain unchanged.

Contextual answers belong in `dialogue_lines.lua` under `M.chat_replies`,
with `sugar`, `rockfruit` and `permission` groups containing `yes`/`no` word lists.
These are whole chat replies to pending questions, without a required name;
do not register them as command IDs or wheel entries. Preserve dialogue keys
and existing voice mappings when editing the reply lists.
