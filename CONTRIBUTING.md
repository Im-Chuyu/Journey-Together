# Journey Together contributions

## Command keywords

Copy `scripts/my_friend_command_words_template.lua` to a new file such as
`scripts/my_friend_command_words_author.lua`. Add the module name to
`scripts/my_friend_command_word_packs.lua`.

Each entry uses this shape:

```lua
{ id = "existing_command_id",
    zh = { "关键词" },
    en = { "english keyword" } },
```

Keywords use substring matching in Chinese and word-boundary matching in
English. The longest matching keyword wins; equal lengths use the earlier
entry. Only existing command ids are accepted by a keyword pack.

## Dialogue

Copy `scripts/my_friend_dialogue_lines_template.lua` to a new file and add its
module name to `scripts/my_friend_dialogue_packs.lua`. Shared lines use the
`lines` table and one-line command responses use `replies`.

Every line must contain both Chinese and English text. Use `{1}` when the
caller supplies a name or other argument. Do not remove required keys from the
default file. Character-specific overrides can be placed in
`scripts/my_friend_dialogue_lines_<character prefab>.lua`.

## Branches

`main` is the stable, released mod branch. `develop` is for integration and
testing. Feature branches should start from `develop` and use a focused name,
for example `feature/dialogue-pack-wendy`.

Before submitting, run the Lua syntax check used by the project and test the
affected command or dialogue in a local DST world.
