# 本机动作与语音助手

助手让你用文字或语音与游戏里的伙伴交谈，也能请模型根据伙伴看到的物品和实际动作回执安排工作。使用游戏自带的伙伴指令时，可以一直关闭「AI大模型模式」。[返回玩家手册](../../docs/player-guide.md) · [English setup](../../docs/en/player-guide.md#optional-local-assistant)

## Windows 开房或加入房间

1. 在模组设置中开启「AI大模型模式」，记下六位游戏配对码，初始为 `321151`。
2. 在自己的 64 位 Windows 电脑上双击模组根目录的 `StartVoice.vbs`。首次启动会检查 Python 3.10+ 与 Tk，缺失时会联网准备。只用文字聊天可以跳过语音模型下载。
3. 在助手中选择下列一种连接方式，让「助手设置」里的**游戏配对码**和房间一致。进入世界，等窗口显示游戏已连接。

| 连接方式 | 设置步骤 |
| --- | --- |
| DeepSeek API | 在「大模型设置」中填写自己的 API Key，保存并重启助手。也可把模组根目录的 `AssistantAPI.example.json` 复制为 `AssistantAPI.json` 后填写 |
| DeepSeek 或豆包网页 | 在 Chrome 或 Edge 的扩展管理页开启开发者模式，加载已解压的 `tools/companion_bridge/browser_extension`。打开并登录模型网页，刷新页面，在扩展中粘贴助手给出的**网页连接码**，选择「连接当前标签页」 |

六位码用来配对游戏，网页连接码用来配对浏览器扩展。网页和 API 都会把对话及本轮所需的游戏状态交给所选模型服务。API 费用由 Key 持有人承担，主动闲聊默认关闭。模型或设置变化后重启助手生效。

### API 配置

[配置示例](../../AssistantAPI.example.json)列出全部字段。通常只需填写 `api_key`。环境变量 `DEEPSEEK_API_KEY` 也可以提供密钥。`AssistantAPI.json` 是本机明文配置，请留在本机。

| 字段 | 默认值 | 用途 |
| --- | --- | --- |
| `provider` | `auto` | Windows 有 Key 时走 API，否则使用网页。Linux 启动脚本默认选 API |
| `model` | `deepseek-flash` | 请求使用的模型 ID |
| `pair_code` | 空 | 留空沿用助手的游戏码，显式填写时用六位数字字符串 |
| `thinking`、`reasoning_effort` | `true`、`low` | 控制思考模式和推理等级 |
| `max_tokens`、`timeout_seconds`、`retries` | `8192`、`120`、`1` | 输出上限、请求超时与临时服务错误重试次数 |
| `ambient_enabled` | `false` | 允许 API 主动闲聊并产生额外调用 |

## Linux 专服

在地面与洞穴分片启用模型模式，选择「常规配对」。在模组根目录从示例复制出 `AssistantAPI.json`，填写自己的 Key 和相同的六位码。使用 Python 3.10 或更新版本，在专服能访问同一回环地址的环境运行：

```sh
sh ./StartAssistantLinux.sh --check-config
sh ./StartAssistantLinux.sh
```

助手在 `127.0.0.1:18766` 监听。有在线玩家和活动伙伴时会自动配对。需要单独保存配置时，给启动器传 `--config /路径/AssistantAPI.json`，或设置环境变量 `MY_FRIEND_ASSISTANT_CONFIG`。

### 云服使用管理员电脑的网页助手

在两个分片选择「管理员客户端」并重启分片。管理员按上面的 Windows 步骤配置助手，进入任一分片并保持在线。游戏使用管理员客户端中继，伙伴仍按**实际发言者**判断工作权限。配对不要求双方在同一分片，递物、复活和跟随等操作要求能在当前分片找到目标。

开启模型后，存档、回档、暂停或恢复、踢人及封禁请求有单独的确认流程。伙伴会追问原因，发言者再答复，由模型评估。管理员中继控制谁能接入助手；这些世界操作的原因审查适用于发起请求的玩家。[世界操作规则](../../docs/BODY_API.md#世界操作)

## 文字、语音与频道

在游戏公屏喊伙伴当前的名字，在助手窗口直接输入即可。跟随状态下由领队安排工作，独立状态下其他玩家也可以安排基础任务。公共聊天可以跨分片，附近私聊遵照游戏原有范围。

- 按住 `F9` 说话，松开后识别。快捷键可改为 F1 至 F12，也可用窗口按钮。选择「安装/准备离线识别」会下载 Whisper 运行库及约 461 MiB 的模型，或选择电脑上已配置的 Windows 系统识别。
- 「本机念出伙伴回复」可选系统音色、语速和音量，默认关闭。朗读在运行助手的电脑上播放。
- 「以玩家身份同步到游戏聊天」会以连接玩家的账号发言，默认关闭。打开「开启私聊」可切换为附近频道。单条同步消息最多 150 个字符。

## 连接排错与数据位置

| 现象 | 检查位置 |
| --- | --- |
| 游戏一直等待配对 | 核对模组开关、专服连接方式和六位码。若此前手动断开，在对应的本地或专服控制台用实际配对码执行 `c_myfriend_ai("start", "321151")`。手动断开使用 `c_myfriend_ai("stop")` |
| 网页有回复，伙伴没说话 | 打开助手的诊断日志，确认连接的是当前已登录的标签页。扩展更新后需重载扩展并刷新模型网页 |
| 助手打不开 | 查看模组目录下的 `tools/companion_bridge/.local/logs/startup-error.log`。可用同目录的 `start.ps1 -CheckOnly` 检查启动环境 |
| 离线识别准备失败 | 查看 `tools/companion_bridge/.local/logs/voice-setup.log`。移动模组目录后可在设置里重新准备语音 |

游戏配对及语音偏好在 `tools/companion_bridge/.local/settings.json`。下载的模型、运行库和日志也在 `.local/`。网页连接码在 Windows 当前用户的 `%LOCALAPPDATA%/JourneyTogether/companion_bridge/web-pairing.json`，其他系统使用 `~/.local/share/JourneyTogether/companion_bridge/web-pairing.json`。更新时保留这些数据。

## 接口与分发

开发者可通过「动作调用」面板或 `--adapter` 接入自选模型。参数、动作回执、任务接管及跨分片边界见[接口文档](../../docs/BODY_API.md)和[适配器示例](provider.example.py)。

制作创意工坊上传目录时，从仓库根目录运行 `python -B tools/companion_bridge/export_workshop.py`。脚本生成独立目录并重新写入空密钥配置。检查导出内容后，再由维护者选择该目录上传。
