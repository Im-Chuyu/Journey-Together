# 一路同行（Journey Together）维护指南

本文件适用于整个模组目录，供后续参与开发的 AI 助手和维护者使用。沟通、修改说明与维护文档优先使用中文；代码标识符沿用现有英文命名。修改前先阅读相关模块及其调用处，以实际代码为准，并在结构或检查方式变化时同步更新本文件。

## 项目概况

- 这是《饥荒联机版》（DST）的伙伴模组，使用 Lua 5.1，`api_version = 10`。
- 模组需要服务端和所有客户端安装，不能按纯客户端模组处理。
- 伙伴在运行时使用真实角色实体，具有跟随、战斗、生存、工作、烹饪、物资整理及角色专属能力；玩家通过聊天、指令轮盘和伙伴面板交互。
- 根目录 `README.md`、`README.en.md` 描述使用方式；翻译贡献规则见 `CONTRIBUTING.md`、`CONTRIBUTING.en.md` 和 `scripts/languages/README.md`。

## 修改入口

| 功能 | 主要文件或目录 |
| --- | --- |
| 模组信息、设置及语言选项 | `modinfo.lua` |
| 注册资源、动作、状态图钩子、RPC、角色和世界初始化 | `modmain.lua` |
| 角色目录与存档包装 prefab | `scripts/my_friend_characters.lua`、`scripts/prefabs/my_friend_characters.lua` |
| AI 行为组装与评分调度 | `scripts/brains/my_friendbrain.lua`、`scripts/behaviours/my_friend_utility.lua` |
| 行为动作执行、寻路与平台适配 | `scripts/behaviours/my_friend_route_action.lua`、`scripts/my_friend_navigation.lua`、`scripts/my_friend_platforms.lua` |
| 聊天转发、指令解析与执行 | `scripts/my_friend_chat.lua`、`scripts/my_friend_commands.lua`、`scripts/my_friend_command_*.lua`、`scripts/my_friend_special_commands.lua` |
| 行为约束、活动范围与权限 | `scripts/my_friend_policy.lua`、`scripts/components/my_friend_affinity.lua` |
| 背包、装备、容器和物品转移 | `scripts/my_friend_inventory*.lua`、`scripts/my_friend_equip_slots.lua`、`scripts/my_friend_backpacks.lua`、`scripts/my_friend_container_*.lua`、`scripts/my_friend_carry_backpack.lua` |
| 客户端初始化与伙伴数据同步 | `scripts/my_friend_client_init.lua`、`scripts/my_friend_replication.lua` |
| 伙伴面板、HUD 按钮、指令轮盘与选择界面 | `scripts/widgets/my_friend_*.lua`、`scripts/screens/my_friend_*.lua` |
| 家园、跨分片迁移、切换角色与附身 | `scripts/my_friend_home.lua`、`scripts/my_friend_shard_home.lua`、`scripts/my_friend_migration.lua`、`scripts/my_friend_switch.lua`、`scripts/my_friend_possess.lua` |
| 角色专属逻辑 | `scripts/my_friend_wendy.lua`、`scripts/my_friend_abigail.lua`、`scripts/my_friend_wortox.lua`、`scripts/my_friend_wanda.lua`、`scripts/my_friend_wormwood.lua`、`scripts/my_friend_wx78.lua` 等 |
| 语言加载、文本、对白与语音 | `scripts/my_friend_language.lua`、`scripts/my_friend_strings.lua`、`scripts/my_friend_dialogue.lua`、`scripts/my_friend_speech.lua`、`scripts/my_friend_voice.lua`、`scripts/languages/` |
| 独立 Lua 回归测试 | `tests/*_test.lua` |
| 图标及声音资源 | `friend.xml`、`friend.tex`、`sound/fsN.fev`、`sound/fsN.fsb` |

食物、生存、农业、基地建设、宠物等逻辑也已拆分为 `scripts/my_friend_*.lua`。先搜索对应功能，优先扩展现有模块；新业务逻辑尽量放入职责明确的模块，`modmain.lua` 保留注册与接线职责。

## 编码与联机约束

- 保持 Lua 5.1 兼容，不使用 `goto`、原生位运算、`utf8` 库或仅新版本存在的 API。沿用四空格缩进、`local` 变量及现有模块的 `local M = {}` / `return M` 风格；中文资源采用 UTF-8，避免编码转换或无关格式化。
- 注意 DST 模组沙箱与普通脚本的区别：`modmain.lua` 中按现有方式通过 `GLOBAL`（本文件中别名为 `_G`）访问游戏全局和未注入的标准函数，不机械地将所有模块改成同一种全局访问方式。
- 修改服务端实体、组件、物品或存档的逻辑应在主模拟端执行，并确认 `TheWorld.ismastersim` 边界。客户端界面读取现有网络变量与 `replica`，通过 RPC 请求服务端执行操作。
- RPC 应校验参数类型、实体有效性、伙伴身份，以及对应操作所需的距离、领队或亲密度权限。沿用 `MyFriends` 命名空间和现有校验函数，不以客户端显示状态代替服务端授权。
- 延迟任务和事件回调执行时重新检查实体及组件；新增监听器、周期任务和临时状态需有清理路径。包装原版方法时保留原方法、参数和返回值，并避免重复安装钩子。
- 伙伴有玩家角色属性，修改原版组件或状态图时应限制影响范围，检查普通玩家是否受到影响。不能随意调用 `locomotor:Stop()` 或切换状态打断 `busy` 状态中的吃饭、攻击、复活等原版动作。
- AI 由效用评分选择行为；新增行为同时考虑评分、动作生成、取消、失败、超时和重新规划。沿用 `Policy`、`RouteAction` 和现有调度约束，避免生存行为被工作任务长期压制。
- 搜索实体、背包扫描和网络同步注意频率；复用已有缓存、冷却与事件驱动刷新，不在每帧重复全世界扫描或无变化广播。

## 存档与物品安全

- 存档使用 `my_friend_<character>` 包装 prefab，运行时仍是实际角色 prefab。保持这一机制及已有名称，尤其不能随意改名 `my_friend_wendy`，旧世界依赖它恢复伙伴。
- 修改持久化状态时检查组件的 `OnSave` / `OnLoad`、`modmain.lua` 的保存钩子，以及家园、跨分片、角色切换和附身的状态转移。新字段允许旧存档缺失并提供合理默认值；字段改名需要兼容读取或迁移。
- 物品移动优先复用现有库存和容器 API，确认堆叠拆分、背包溢出、归属、装备槽和客户端刷新。涉及牛铃绑定皮弗娄牛等关联实体时，参照 `my_friend_inventory_transfer.lua`，避免重复生成、遗失或留下孤立实体。
- 不直接修改玩家的真实存档来验证功能；保存恢复和跨分片验证使用测试世界。

## 指令、语言与语音更新

- 通用指令词位于 `scripts/languages/<code>/command_words.lua`；角色指令位于 `characters/<character>_command_words.lua`，使用稳定的 `id`、本语言 `keywords` 和轮盘显示 `label`。
- 新增可执行指令时，同步检查 `my_friend_commands.lua` 的注册/分派、相关执行模块、AI 行为和轮盘目录；仅增加关键词不能替代执行逻辑。聊天与轮盘入口应保持一致，并保留重复转发去重机制。
- 当前语言目录包含 `zh`、`zh_tw`、`en`、`ru`，新增语言可参考 `_template`。纯翻译工作只修改语言文件，保留既有指令 ID 和对白键；维护者集成新语言时再按需要更新 `modinfo.lua`。
- 共享台词使用 `dialogue_lines.lua`，角色台词使用 `characters/<character>.lua`。沿用 `lines`、`replies` 和 `{1}` 参数占位符；每个语言文件只包含对应语言，保留缺失资源回退机制。
- 关键词匹配存在边界和优先级规则，修改时检查 `Contains` 与解析逻辑，验证中文子串、英文词边界、长关键词、伙伴称呼及角色专属指令，避免扩大误触发范围。
- 中文自定义语音按银行每组 70 个事件组织，路径形如 `fsN/fsN/fnK`，编号跨银行连续。新增映射采用 `{"key", line_index, fn_number}`；编号永久绑定音频，不能复用或因文本排序重新编号。简繁中文对应台词保持相同 `fn_number`，字符专属映射也需检查对应音频。
- 添加声音银行时同步检查 `modmain.lua` 的 `Assets` 注册、语音查找和实际 `.fev` / `.fsb` 文件；不要在没有资源的情况下只增加映射，也不要无关重写二进制资源。

## 检查与验证

在模组根目录执行命令。环境需要 Lua 5.1 的 `lua` 和 `luac`；若不在 PATH，使用实际可执行文件路径。语法检查使用 `luac -p`，不要生成或提交 `luac.out`。

检查全部 Lua 文件（PowerShell）：

```powershell
$files = @(rg --files -g '*.lua')
foreach ($file in $files) {
    & luac -p $file
    if ($LASTEXITCODE -ne 0) { throw "Lua 语法检查失败：$file" }
}
```

运行单项回归测试，例如聊天指令：

```powershell
lua tests/chat_command_test.lua
```

运行全部现有回归测试，每个文件使用独立 Lua 进程：

```powershell
$tests = @(rg --files tests -g '*_test.lua' | Sort-Object)
foreach ($test in $tests) {
    & lua $test
    if ($LASTEXITCODE -ne 0) { throw "回归测试失败：$test" }
}
```

- 按影响范围选择测试：聊天解析与转发使用 `chat_address_test.lua`、`chat_command_test.lua`；背包和关联实体转移使用 `carry_backpack_test.lua`、`inventory_transfer_test.lua`；面板显示使用 `panel_badges_test.lua`、`panel_scroll_test.lua`；阿比盖尔与沃拓克斯使用相应角色测试。
- 修复复杂行为或可复现回归时，沿用现有桩对象风格补充能检验实际行为的测试；文档、简单文本和低影响调整无需为了覆盖率新增测试。
- 这些测试模拟了部分 DST 接口，不能证明真实联机、状态图或跨分片行为正确。涉及这些功能时，在游戏测试世界中验证主机和远程客户端，按需测试专用服务器、地上/洞穴迁移、保存重进、死亡复活、角色切换或附身。
- UI 修改检查快捷键、轮盘分页与替换、伙伴面板装备/背包槽、滚动和不同分辨率；语言修改检查实际指令、台词、标签及回退。只检查本次修改涉及的场景。

## 工作方式与交付

- 开始前检查 Git 状态和当前分支，保留已有未提交改动；不要擅自重置、覆盖或清理与任务无关的内容。
- 仓库文档约定 `main` 为稳定版、`develop` 为集成开发分支，功能工作从 `develop` 开始。需要新建分支时，Codex 默认使用 `codex/<主题>`；用户指定分支名称或工作位置时按其要求执行，不为了单纯文档修改自动切换分支。
- 只修改任务所需文件，不随意提升 `modinfo.lua` 版本、改作者或发布配置。功能、设置、指令或语言贡献流程变化时同步更新对应 README/贡献文档。
- 完成后检查差异，说明改动内容、执行过的检查以及尚未进行的游戏验证；不能把桩测试通过描述为游戏实测通过。提交、推送和发布按当前任务授权范围执行。
