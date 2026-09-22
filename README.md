# Journey Together

饥荒联机版模组：一路同行（Journey Together）。伙伴可以跟随玩家、协助战斗、独立生存、整理物资、制作料理，并通过聊天指令执行工作。

## 分支

- `main`：稳定发布版本，适合直接下载和使用。
- `develop`：下一版本开发和联调分支。
- `feature/*`：从 `develop` 创建的单项功能分支。

## 台词与关键词扩展

中文默认文件和英文文件分别是：

- `scripts/my_friend_command_words_zh.lua`
- `scripts/my_friend_command_words_en.lua`
- `scripts/my_friend_dialogue_lines_zh.lua`
- `scripts/my_friend_dialogue_lines_en.lua`

中文是默认语言。旧的 `my_friend_command_words.lua` 和
`my_friend_dialogue_lines.lua` 仅保留为兼容入口，不再编辑它们。

为了方便贡献者扩展，项目提供了可配置文件：

- `scripts/my_friend_command_word_packs.lua`：登记额外关键词模块。
- `scripts/my_friend_dialogue_packs.lua`：登记额外台词模块。
- `scripts/my_friend_command_words_template.lua`：关键词模板。
- `scripts/my_friend_dialogue_lines_template.lua`：台词模板。
- `scripts/my_friend_command_words_template_en.lua`：英文关键词模板。
- `scripts/my_friend_dialogue_lines_template_en.lua`：英文台词模板。

新增语言时，复制对应模板并使用语言代码命名，例如 `ja` 对应
`my_friend_command_words_ja.lua` 和 `my_friend_dialogue_lines_ja.lua`，然后在
`modinfo.lua` 的 `language` 选项中加入 `ja`。完整格式和命名规则见
[`CONTRIBUTING.md`](CONTRIBUTING.md)。台词和关键词文件只填写一种语言，缺失文件会回退到中文。

## 本地检查

在 `scripts` 目录执行 Lua 5.1 语法检查后，再进入 DST 世界测试对应指令、台词和多人客户端显示。
