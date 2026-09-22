-- Optional shared dialogue packs.
--
-- Add a base module name here. The loader selects <module>_<language>.lua and
-- falls back to <module>_zh.lua. Each module returns:
--     { lines = { key = { { "one line" }, { "another line" } } },
--       replies = { key = { "one reply" } } }
-- Character-specific files remain supported through
-- my_friend_dialogue_lines_<prefab>_<language>.lua.
return {}
