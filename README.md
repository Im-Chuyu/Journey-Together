# Journey Together

饥荒联机版模组：一路同行（Journey Together）。伙伴可以跟随玩家、协助战斗、独立生存、整理物资、制作料理，并通过聊天指令执行工作。

## 分支

- `main`：稳定发布版本，适合直接下载和使用。
- `develop`：下一版本开发和联调分支。
- `feature/*`：从 `develop` 创建的单项功能分支。

## 指令轮盘

按 `Alt` + 模组设置中的快捷键（默认 `Alt+R`）打开伙伴指令轮盘。右键轮盘按钮可从完整指令目录替换该位置的指令；目录支持分页，也允许重复指令。快捷键可在 `modinfo.lua` 的“指令轮盘快捷键”选项中设置为 `Alt+A`–`Alt+Z` 任一组合。

通用指令放在 `scripts/languages/<语言代码>/command_words.lua`。角色专属指令放在 `scripts/languages/<语言代码>/characters/<角色>_command_words.lua`，例如 `characters/wickerbottom_command_words.lua`。每条指令需保留稳定的 `id`，并填写对应语言的 `keywords` 和轮盘显示 `label`。轮盘会汇总通用指令与所有角色专属指令；新增角色指令文件后会自动加入目录。

## 台词与语音

中文是默认语言。默认台词位于 `scripts/languages/<语言代码>/dialogue_lines.lua`，角色专属台词位于 `scripts/languages/<语言代码>/characters/<角色>.lua`；缺少专属台词时回退到温蒂的默认台词。

简体中文角色台词中的 `voice_order` 按顺序对应自定义语音事件编号。每个音频银行包含 70 个事件，资源放在 `sound/fsN.fev` 和 `sound/fsN.fsb`，引用路径形如 `fsN/fsN/fnK`，`K` 在不同银行间连续编号。模组设置中的“伙伴语音”选项控制自定义语音；自定义语音目前只用于简体中文和繁体中文，其他语言使用角色原生声音。

语言贡献者只需提交语言文件，不需要修改核心代码、包清单或 `modinfo.lua`。主开发者审核并合并语言文件后，再在 `modinfo.lua` 增加语言选项。新增语言时可复制 `scripts/languages/_template`；格式和命名规则见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。缺少语言文件时会回退到中文。

## 本地检查

执行 Lua 5.1 语法检查后，再进入 DST 世界测试对应指令、台词和多人客户端显示。
