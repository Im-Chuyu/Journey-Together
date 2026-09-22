# Journey Together

饥荒联机版模组：AI伙伴（Journey Together）。伙伴可以跟随玩家、协助战斗、独立生存、整理物资、制作料理，并通过聊天指令执行工作。

## 分支约定

- `main`：稳定发布版本，适合直接下载和使用。
- `develop`：下一版本开发和联调分支。
- `feature/*`：从 `develop` 创建的单项功能分支。

## 台词与关键词扩展

核心默认文件仍是：

- `scripts/my_friend_command_words.lua`
- `scripts/my_friend_dialogue_lines.lua`

为了方便贡献者扩展，项目提供了可插拔文件：

- `scripts/my_friend_command_word_packs.lua`：登记额外关键词模块。
- `scripts/my_friend_dialogue_packs.lua`：登记额外台词模块。
- `scripts/my_friend_command_words_template.lua`：关键词模板。
- `scripts/my_friend_dialogue_lines_template.lua`：台词模板。

完整格式和命名规则见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。新增关键词只能使用已有指令 `id`；新增行为需要同步提交对应代码。台词文件必须同时提供中文和英文文本，客户端才能正确显示聊天内容。

## 本地检查

在 `scripts` 目录执行 Lua 5.1 语法检查后，再进入 DST 世界测试对应指令、台词和多人客户端显示。
