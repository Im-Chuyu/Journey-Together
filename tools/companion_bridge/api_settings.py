"""Desktop editor for the local API configuration; changes apply after restart."""
import tkinter as tk
from tkinter import ttk

from . import api_config

PROVIDERS = {"自动选择（填Key用API）": "auto", "DeepSeek API": "deepseek-api", "模型网页": "web",
             "DeepSeek 网页": "deepseek-web", "豆包网页": "doubao-web", "离线演示": "demo"}
EFFORTS = {"低（low）": "low", "高（high）": "high", "最高（max）": "max"}


def show(parent, path=None):
    window = tk.Toplevel(parent)
    window.title("大模型设置")
    window.transient(parent)
    window.resizable(False, False)
    try:
        # Do not reveal or accidentally persist an environment-only credential.
        config = api_config.load(path, resolve_env=False)
    except (ValueError, OSError) as error:
        ttk.Label(window, text=str(error), wraplength=480).pack(padx=16, pady=16)
        return window
    body = ttk.Frame(window, padding=16)
    body.pack(fill="both", expand=True)
    body.columnconfigure(1, weight=1)

    def choice(row, name, label, values, current, readonly=True):
        ttk.Label(body, text=label).grid(row=row, column=0, sticky="w", padx=(0, 12), pady=5)
        widget = ttk.Combobox(body, name=name, values=tuple(values), width=32,
                              state="readonly" if readonly else "normal")
        widget.set(current)
        widget.grid(row=row, column=1, sticky="ew", pady=5)
        return widget

    provider = choice(0, "provider", "连接方式", PROVIDERS,
                      next(label for label, value in PROVIDERS.items() if value == config["provider"]))
    ttk.Label(body, text="API Key").grid(row=1, column=0, sticky="w", pady=5)
    key = ttk.Entry(body, name="api_key", show="*", width=34)
    key.insert(0, config["api_key"])
    key.grid(row=1, column=1, sticky="ew", pady=5)
    model = choice(2, "model", "模型（可填写模型ID）", ("deepseek-flash", "deepseek-v4-pro"), config["model"], False)
    thinking = tk.BooleanVar(window, value=config["thinking"])
    effort = choice(4, "effort", "思考等级", EFFORTS,
                    next(label for label, value in EFFORTS.items() if value == config["reasoning_effort"]))

    def update_effort():
        effort.configure(state="readonly" if thinking.get() else "disabled")

    ttk.Checkbutton(body, name="thinking", text="启用思考模式", variable=thinking,
                    command=update_effort).grid(row=3, column=1, sticky="w", pady=5)
    update_effort()
    numbers = {}
    for row, name, label, low, high in (
        (5, "max_tokens", "输出上限（含推理）", 512, 32768),
        (6, "timeout_seconds", "网络超时（秒）", 10, 300),
        (7, "retries", "临时服务错误重试次数", 0, 2),
    ):
        ttk.Label(body, text=label).grid(row=row, column=0, sticky="w", padx=(0, 12), pady=5)
        variable = tk.StringVar(window, value=str(config[name]))
        ttk.Spinbox(body, name=name, from_=low, to=high, textvariable=variable,
                    width=32).grid(row=row, column=1, sticky="ew", pady=5)
        numbers[name] = variable
    ambient = tk.BooleanVar(window, value=config["ambient_enabled"])
    ttk.Checkbutton(body, name="ambient", text="允许API主动闲聊（会产生调用费用）",
                    variable=ambient).grid(row=8, column=0, columnspan=2, sticky="w", pady=5)
    ttk.Label(body, text="仅DeepSeek API使用这些参数，网页模式按网页设置。Key留空可使用环境变量。\n"
                        "高思考等级可能增加等待与Token消耗；具体以模型支持为准。\n"
                        "保存至模组根目录AssistantAPI.json，重启助手生效。",
              wraplength=500).grid(row=9, column=0, columnspan=2, sticky="w", pady=(8, 5))
    hint = ttk.Label(body, name="hint", text="", wraplength=500)
    hint.grid(row=10, column=0, columnspan=2, sticky="w", pady=5)

    def apply():
        try:
            try:
                values = {name: int(variable.get()) for name, variable in numbers.items()}
            except ValueError:
                raise ValueError("输出上限、超时和重试次数必须填写整数。") from None
            values.update(pair_code=config["pair_code"], provider=PROVIDERS[provider.get()], api_key=key.get().strip(),
                          model=model.get().strip(), thinking=thinking.get(),
                          reasoning_effort=EFFORTS[effort.get()], ambient_enabled=ambient.get())
            api_config.save(values, path)
            hint.configure(text="已保存，重启助手后生效；当前任务继续使用原参数。")
        except (ValueError, OSError) as error:
            hint.configure(text=str(error))

    ttk.Button(body, name="save", text="保存", command=apply).grid(row=11, column=0, columnspan=2, pady=8)
    return window
