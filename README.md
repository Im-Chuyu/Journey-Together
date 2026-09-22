# Journey Together

饥荒联机版模组：一路同行（Journey Together）。伙伴可以跟随玩家、协助战斗、独立生存、整理物资、制作料理，并通过聊天指令执行工作。

## 分支

- `main`：稳定发布版本，适合直接下载和使用。
- `develop`：下一版本开发和联调分支。
- `feature/*`：从 `develop` 创建的单项功能分支。

## 台词与关键词扩展

中文是默认语言。语言贡献者只需要提交语言目录中的两个文件：

- `scripts/languages/<语言代码>/command_words.lua`
- `scripts/languages/<语言代码>/dialogue_lines.lua`

贡献者不需要修改核心代码、包清单或 `modinfo.lua`。主开发者审核并合并
语言文件后，再在 `modinfo.lua` 增加语言选项，下载仓库代码即可发布到模组。

新增语言时，复制 `scripts/languages/_template` 为 `scripts/languages/ja`，然后由
主开发者在 `modinfo.lua` 的 `language` 选项中加入 `ja`。完整格式和命名规则见
[`CONTRIBUTING.md`](CONTRIBUTING.md)。台词和关键词文件只填写一种语言，缺失文件会回退到中文。

## 本地检查

在 `scripts` 目录执行 Lua 5.1 语法检查后，再进入 DST 世界测试对应指令、台词和多人客户端显示。
