# 开源项目调研草案

初始调研日期：2026-09-17；本地源码补充：2026-09-18。原候选比较仍待联网核验；Mac-Agent-Beacon 已阅读用户下载的本地源码，详见末节。

## 证据边界

前次已实际查看 Google 搜索结果，发现下列 GitHub 项目。GitHub 仓库搜索返回 secondary rate limit；本次恢复调研时，浏览器工具及公开文档网络请求的自动审批服务均返回 503，受限 shell 也无法解析外网域名。因此：

- 下表的“功能”来自已看到的搜索摘要；不据此保证实际版本行为。
- 原候选表中的仓库 README、源码、维护活跃度、许可证、硬件兼容性均未完成核验。
- 不虚构 stars、提交日期、测试覆盖率或 Packy Code 支持。
- 技术栈、架构没有证据的地方明确列为待查，而不是把推荐方案当成已有项目实现。

## 候选比较

| 项目 | 搜索中可见功能 | 架构／技术栈核实状态 | 对本项目的参考价值 | 局限与必须确认的点 |
| --- | --- | --- | --- | --- |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | macOS 菜单栏用量仪表；不同提供商的用量窗口、余额、重置倒计时；错误／过期状态提示 | 菜单栏应用定位已见；采集器分层、Swift 版本、依赖及 CLI 边界须读源码确认 | 最接近用量展示需求；值得优先研究提供商适配与过期数据设计 | 未验证 Packy Code；账户限额不等于第三方 API 余额；未验证任务审批事件或 LED 能力 |
| [burakereno/codex-monitor](https://github.com/burakereno/codex-monitor) | 原生 macOS 菜单栏；Codex 5 小时／每周用量、重置时间和 credits | 原生 macOS 定位已见；具体语言、数据来源和轮询方式待核实 | 聚焦 Codex，适合比较较小产品的界面及采集范围 | 搜索摘要未证明支持第三方计费；“monitor”名称不能证明能监控项目运行与审批状态 |
| [yizhigou/codex-usage-bar](https://github.com/yizhigou/codex-usage-bar) | 原生 macOS 菜单栏与 Touch Bar 的 Codex 用量监控 | 多输出界面定位已见；共用数据模型、框架与实现细节待核实 | 值得研究一份用量数据驱动多个显示出口的方式 | Touch Bar 与 Caps Lock LED 不是同一硬件接口；不应直接推定能复用其驱动 |
| [busyloop/maclight](https://github.com/busyloop/maclight) | 搜索结果中被引用为 OS X 键盘 LED 控制工具 | 具体语言、IOKit／HID 调用、权限及 Apple Silicon 支持待读源码和实机核实 | 最直接的 LED 层研究候选，可帮助确认灯与 Caps Lock 逻辑状态能否独立控制 | 搜索线索来自旧问答；不能证明适用于当前 MacBook；没有证据证明包含 Codex 状态或用量能力 |

以上优缺点是针对本需求的适配判断，不代表已经验证各项目没有某项功能。

## 初步选择

1. **以 CodexBar 为主要用量产品参考。** 若源码核验后其提供商扩展机制及许可证适合，可评估 fork；目前不直接复制代码。
2. **以 maclight 为 LED 技术线索。** 先确认当前硬件可行性，再决定是复用、移植，还是使用另一条直接 LED 输出接口。
3. **codex-monitor 与 codex-usage-bar 作为界面及范围对照。** 重点核查依赖规模、刷新策略、睡眠恢复以及过期数据显示。
4. **暂定独立原生应用。** 用户要求额外的任务状态聚合与硬件输出，单纯修改用量显示并不能覆盖这些需求。源码调研完成后再锁定“独立开发”还是“扩展现有项目”。

## 正式调研还需要回答的问题

对各仓库记录固定 commit、许可证、入口、数据采集模块、状态模型、依赖清单、测试与最近维护情况。每个架构结论应给出 README 或源码文件链接。

### Codex Desktop／CLI

- 从官方文档核查生命周期 hooks 的真实事件名称和 payload；不能先假设存在 start、approval-resolved、input-resolved 等完整事件。
- 核查 app-server 的请求、响应与通知协议，以及第三方是否能订阅**已有 Desktop 实例**。自己启动一个 app-server 不等于看到了 Desktop 正在运行的任务。
- 确认结构化审批请求、请求解决、结构化输入、重试、终止错误及完成事件是否都能观测。
- 日志或 rollout 文件是否包含完整结构化事件、稳定 task/turn ID，以及能否可靠区分无输出与观察器断线。
- 若事件不完整，应在方案中公开精度限制，不能用聊天文本或无输出超时补造审批状态。

官方文档核验入口：[Codex App Server](https://developers.openai.com/codex/app-server/)（本次尚未成功读取，不能作为已核实依据）。

### Packy Code

- **已确认身份**：用户明确提供 [Packy Code 官方文档](https://docs.packyapi.ai/)。文档正文尚未成功读取，不能据此声称任何具体接口存在。
- 是否有只读余额、消费记录、套餐限额、重置时间接口？使用 API key、独立只读 token，还是网页会话？
- API 返回的是账户余额、特定 key 的额度，还是套餐周期已用量？币种和折扣口径是什么？
- OpenAI 兼容推理接口并不自动提供兼容的余额／账单接口。
- 若没有可用查询 API：先支持本地 token 统计及用户预算；明确标注“估算”，真实余额显示“暂不可查询”，不默认为 0。

接入设计见 [Packy Code 接入契约](packy-integration.md)。这里的接口能力、认证字段与数据字段都是核验清单，不是从官方文档抄录的 API 定义。

## 研究结论的当前强度

已经有适合进一步阅读的开源候选，但尚不足以承诺 LED 硬件兼容性、Desktop 完整观察能力或 Packy Code 余额查询。下一阶段必须先验证这三个条件，再开展完整实现。

## Mac-Agent-Beacon：已阅读本地源码

来源：[rynzh/Mac-Agent-Beacon](https://github.com/rynzh/Mac-Agent-Beacon)。用户下载路径 `/Users/leslie/git/Mac-Agent-Beacon`，本次阅读版本 `d18d652215bfb8f0ca20b532adffaecafa9987c5`。阅读范围为 README、LICENSE、THIRD_PARTY_NOTICES、docs/SAFETY、native/led.c 和 bin/codex-live.rb；没有运行安装器、启动后台服务或实测它的控灯效果。

| 维度 | 已核实的实现 | 对 Codex Signal 的意义 |
| --- | --- | --- |
| 架构 | Ruby 控制层、C HID helper、本地状态文件；LED helper 用标准输入接收 `0/1/r/q` | 可以单独诊断硬件。我们的 Swift 应用与 CLI 共用驱动，不需要引入 Ruby 常驻服务 |
| 设备选择 | 产品名 `Apple Internal Keyboard / Trackpad` + Keyboard usage，再找 Caps Lock LED Output | 我们保留 `Built-In` 标记筛选，避免依赖单一产品名称；外接设备不在范围内 |
| 打开方式 | `IOHIDManagerCopyDevices` 枚举，找到元素后 `IOHIDDeviceOpen` 目标设备，没有先 `IOHIDManagerOpen` | 已将本项目改为目标设备级打开，并在释放时成对关闭 |
| 实际写入 | `IOHIDValueCreateWithIntegerValue` → `IOHIDDeviceSetValue` | 两者底层写灯接口一致；参考项目没有通过模拟按键让灯亮 |
| 退出恢复 | EOF、退出命令、信号结束后按当前逻辑 Caps Lock 状态恢复灯 | 本项目应用释放、自检受控退出也尝试恢复；强制杀进程仍不保证恢复 |
| 权限 | README 明确要求为具体 helper 路径手动授予 Input Monitoring 并重启 | 已补充本项目 CLI 与应用分别授权的说明，不能把设备级打开当作免授权方案 |
| Desktop 实时状态 | `bin/codex-live.rb` 读取私有 `~/.codex/ipc/ipc.sock`，4 字节小端长度帧，状态版本 11；订阅快照／补丁并核对 revision | 这是与我们现有 app-server 不同的协议，提供后续适配线索；不能直接把该 socket 填进 app-server 设置 |
| 审批识别 | 对照结构化 requests 方法和 activeFlags；运行时错误或活跃任务的观察连接丢失发布 attention | 符合不猜测聊天文本的方向；还需在目标 Desktop 版本做协议兼容性验证 |
| 用量范围 | 已读部分围绕任务与 LED，没有提供 Packy 官方账单接口证据 | 不解决当前余额查询接口尚未核验的问题 |

**优点：** 控灯层小、设备级访问、输入协议明确，权限步骤具体；Desktop 私有 IPC 代码给出了可研究的真实协议形状。

**限制：** 硬编码键盘产品名；依赖手动授权；可能受其他 HID 控制软件和系统灯状态更新影响；Desktop 私有协议固定版本，升级后可能失效。源码存在不代表已经在本机验证通过。

**许可证：** 仓库为 MIT。`native/led.c` 声明改编自 CapsPulse，`THIRD_PARTY_NOTICES.md` 包含其 MIT 许可及来源 commit `6f204081aaceb139d18de3239cd99138179b3a5c`。本次基于已存在的 Swift 驱动调整系统 API 的打开／关闭顺序，没有复制 C helper 或 Ruby 实现；未来若复用其代码，应随分发保留适用许可与版权声明。

**采用范围：** 已采用设备级打开思路和权限排查信息。随后新增独立 Swift Desktop IPC 观察器，并从本机客户端核对状态协议版本 11 和订阅版本 1；它在 app-server 地址为空时自动连接，详见 README 和验证报告。没有执行 `install.sh`、`persistence.rb` 或 `try-system-mapping.rb`，后两者涉及旧键位映射，不属于本项目只控制 LED 的目标。
