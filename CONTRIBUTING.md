# 参与一路同行

[English](docs/en/contributing.md) · [开发文档](docs/DEVELOPER.md) · [语言文件规范](scripts/languages/README.md)

## 反馈游戏问题

在 [Issues](https://github.com/Im-Chuyu/Journey-Together/issues) 说明模组版本、使用的角色、房主开房还是独立服务器，以及问题发生在地面还是洞穴。请写出从哪一步开始能看到异常、你原本期待什么。若有 Lua 报错，附上第一条错误和完整调用栈。日志可能含个人信息，贴出相关片段即可。

## 提交翻译

1. 从 `develop` 创建分支。在已有语言目录中修改文本，或将[语言模板](scripts/languages/_template)复制为 `scripts/languages/<语言代码>/`。可以对照[英文](scripts/languages/en)或[俄文](scripts/languages/ru)目录。
2. 通用指令写入 `command_words.lua`，对白写入 `dialogue_lines.lua`，棋盘界面用 `games.lua`。角色专属台词和轮盘词条放在该语言的 `characters/` 下。
3. 保留指令 ID、对白键、语音编号和占位符，例如 `{1}` 或 `%s`。同一条消息命中多个指令词时，以最长者优先，等长按原顺序。新增语言由维护者登记到模组设置。
4. 提交到 `develop`，注明语言、涉及的文件，以及实际检查过的关键词或界面。翻译提交只包含对应的语言文件。

## 修改代码或文档

`main` 对应公开版本，`develop` 用于集成。请从 `develop` 开始，每项改动说明一个具体问题和验证结果，提交与合并说明使用英文。Lua 代码遵循 5.1，文件用 UTF-8 和四空格缩进。

玩家操作写在[伙伴手册](docs/player-guide.md)，系统规则和模块索引在[开发文档](docs/DEVELOPER.md)，接口参数在[伙伴动作接口](docs/BODY_API.md)。验证范围按实际改动选择。个人助手配置、密钥、存档和本地测试目录请留在本机。
