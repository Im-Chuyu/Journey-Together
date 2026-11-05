# 一路同行：维护入口

适用于整个模组目录。沟通和维护文档优先中文；修改前阅读相关代码及调用处，以实际实现为准。

## 先读哪里

- 完整架构、系统规则、模块索引、排错和测试地图：[DEVELOPER.md](DEVELOPER.md)。
- 使用说明：[README.md](README.md)、[README.en.md](README.en.md)。
- 翻译规范：[CONTRIBUTING.md](CONTRIBUTING.md)、[scripts/languages/README.md](scripts/languages/README.md)。

## 主要入口

| 范围 | 文件（业务模块位于 `scripts/`） |
| --- | --- |
| 注册、RPC、初始化、保存接线 | `modmain.lua`；配置为 `modinfo.lua` |
| AI 与动作 | `brains/my_friendbrain.lua`、`behaviours/my_friend_utility.lua`、`behaviours/my_friend_route_action.lua` |
| 指令与权限 | `my_friend_chat.lua`、`my_friend_commands.lua`、`my_friend_special_commands.lua`、`my_friend_policy.lua`、`components/my_friend_affinity.lua` |
| 移动、战斗与生存 | `my_friend_navigation.lua`、`my_friend_platforms.lua`、`my_friend_behavior_ai.lua`、`my_friend_combat_rules.lua`、`my_friend_dodge*.lua`、`my_friend_food*.lua`、`my_friend_equipment.lua` |
| 基地与库存 | `my_friend_base_ai.lua`、`my_friend_home.lua`、`my_friend_inventory*.lua`、`my_friend_container*.lua`、`my_friend_storage.lua` |
| 保存、迁移与换体 | `prefabs/my_friend_characters.lua`、`my_friend_inventory_transfer.lua`、`my_friend_migration.lua`、`my_friend_shard_home.lua`、`my_friend_switch.lua`、`my_friend_possess.lua` |
| 角色能力 | 对应 `my_friend_<character>.lua`；读书另查 `my_friend_books.lua`，救援查 `my_friend_rescue.lua` |
| 客户端与语言 | `my_friend_client_init.lua`、`my_friend_replication.lua`、`widgets/`、`screens/`、`my_friend_speech.lua`、`my_friend_voice.lua`、`languages/` |

## 必须保留的约束

- Lua 5.1、UTF-8、四空格；`modmain.lua` 的游戏全局按现有方式经 `GLOBAL` 访问。服务端和所有客户端均需模组。
- 伙伴运行时是真实角色，存档使用 `my_friend_<character>` 包装；保留 `my_friend_wendy` 等旧名称与旧档默认值。影响库存/身体状态时同时检查保存、迁移和附身。
- 业务在主模拟端执行；客户端只显示和请求。RPC 校验类型、活动伙伴身份、归属、距离及适用权限；聊天和轮盘走一致入口。
- 复用现有模块、Policy、RouteAction 和效用调度；不要强停 busy 动作。延迟回调重验实体/组件，包装保留原方法并防重复，任务和监听器必须能清理。
- 物品移动走原版库存/容器接口；注意堆叠、活动物品、背包和绑定牛。PICKUP 可能已自动装备，不得对同件装备重复 Equip。
- 搜索和同步复用缓存/事件，无变化不广播；帧级躲避不代表帧级全行为扫描或重复寻路。临时路线/帧状态不存实体引用进存档。
- 食物主动选食、玩家喂食和入锅规则分开；角色饮食限制保留。角色专属行为必须有角色门槛，书架记忆不做周期扫描；救援不加跟随门槛。细则见开发文档。
- 指令使用稳定 ID，更新解析、执行、权限、AI、轮盘和语言；台词保留占位符及回退。语音每银行 70 条，fn 编号永久绑定，不重排、不复用，不无关改二进制声音资源。

## 检查与交付

- 开始检查 `git status` 和当前分支，保留用户已有改动。新功能约定从 `develop` 开始，新分支默认 `codex/<主题>`；用户指定分支/位置优先。
- 仅改任务文件，不擅自改版本号、作者或发布设置。系统规则更新 `DEVELOPER.md`，用法更新 README；本文件保持简短。
- 默认不跑全量测试、全目录语法检查或启动游戏验证。文档、语言、注释及简单低风险修改只做差异检查；普通代码修改以阅读受影响调用链为主，必要时只对修改的 Lua 文件运行 `luac -p`（不生成 `luac.out`）。不要求每次改代码都运行回归或新增测试。
- 只有修改涉及实质行为风险、出现具体疑点或用户明确要求时，选择能验证该风险的最少定向检查；能由阅读差异或语法检查确认的小改动到此结束。不得因存在测试目录、涉及多个模块或准备发布而批量运行测试；不自动扩展到相邻系统，已通过的不重复跑。全量测试仅在用户明确要求时执行。差异检查包含 `git diff --check`，新文件暂存后另查 `git diff --cached --check`。
- `tests/` 整个目录仅供本地使用，由 Git 忽略，不提交；临时产物放 `tests/.local/`，不写系统 Temp。不为普通修改新增测试，也不恢复用户已删除的测试文件或目录；删除本地测试不影响模组运行。
- 交付后清理本次生成的临时导出和可重建缓存，不累积完整发布副本。助手设置、密钥、语音模型/运行库和游戏存档不能当缓存删除；需要保留的备份集中存放。
- 桩测试不等于游戏实测；远程客户端、保存重进、跨分片和角色交换仅在本次风险确实需要时验证，未验证如实说明，不用真实玩家存档做破坏性测试。
- 交付说明修改、验证及未验证部分。提交、推送、发布按任务授权执行。
