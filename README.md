# CodePulse

**用 Mac 菜单栏查看 Codex 任务状态，并让 Caps Lock 指示灯提醒你何时需要处理任务。**

CodePulse 是一个 Swift 原生 macOS 项目。菜单栏和 Caps Lock LED 可以独立开关；同一套状态核心负责多个任务的聚合。应用还提供本地历史记录、PackyCode 账户余额查询，以及可配置的 HTTPS JSON 用量查询。

当前预览版的应用名称仍为 **Codex Signal**，命令行工具为 `signalctl`。下文的应用名称、构建产物及设置位置与实际程序一致，已有设置、钥匙串凭据和权限标识保持兼容。

> **版本：0.1.0 本地预览版。** 本机 Desktop 实时连接和应用 LED 控制已经过用户验证。PackyCode 余额适配已依据 All API Hub 的 New API 调用链实现并通过模拟测试，首次使用仍需与真实控制台对账；不保证观察任意版本 Codex Desktop 的所有任务。

## 目录

- [当前实现范围](#当前实现范围)
- [快速开始](#快速开始)
- [状态灯如何工作](#状态灯如何工作)
- [连接 Codex 任务](#连接-codex-任务)
- [配置用量与余额](#配置用量与余额)
- [设置与数据](#设置与数据)
- [构建与测试](#构建与测试)
- [架构与源码](#架构与源码)
- [故障排查](#故障排查)
- [验证记录与后续工作](#验证记录与后续工作)

## 当前实现范围

| 能力 | 当前状态 | 使用条件或限制 |
| --- | --- | --- |
| 原生顶部菜单栏和详情窗口 | 已实现、已编译 | 任务、用量、设置三个页面；窗口关闭后后台仍运行 |
| 仅菜单栏／仅 LED／两者同时开启 | 已实现 | LED 默认关闭；重新打开应用可找回设置 |
| 多任务注意力优先 | 已通过自动化测试 | 只聚合收到的结构化事件 |
| 普通文字不推断审批 | 已通过自动化测试 | 不分析聊天内容中的“approve”等字样 |
| 临时重试与终止错误分离 | 已通过自动化测试 | Codex 错误通知必须包含 `willRetry` |
| Desktop IPC 自动观察 | 已实现、本机 CLI 连接验证通过 | 已收到当前活跃任务的实时状态；私有 v11 协议，完整审批／异常链路仍待实机验收 |
| app-server 只读观察 | 已实现、模拟协议测试通过 | 需要已有服务器 socket；真实 Desktop 连接尚未端到端验证 |
| Desktop 本地历史列表 | 已实现、数据库测试通过 | 读取指定版本 SQLite 元数据；历史状态不驱动 LED |
| CLI／hook 事件入口 | 已实现 | `signalctl emit` 和 `bridge`；不自动修改或安装 Codex hooks |
| 直接写入 Caps Lock LED | 本机 CLI 自检及应用控灯确认通过 | 用户已确认应用 LED 测试成功；完整睡眠恢复及其他设备仍待验证 |
| 通用余额、用量比例查询 | 已实现、解析测试通过 | 用户配置确认过的 HTTPS GET 地址、字段、单位和凭据 |
| PackyCode 账户余额 | 已实现、模拟测试通过 | 账户访问令牌 + 用户 ID；New API 兼容接口，真实账号对账待完成 |
| 侧边浮窗、自动启动、自动更新 | 未实现 | 本版优先菜单栏；不会安装登录项或系统服务 |

使用前先明确三个概念：

- **实时任务**：来自 Desktop IPC、已连接的 app-server 或事件桥接，可以驱动 LED。
- **历史记录**：来自本地数据库，可能陈旧，只供查看。
- **账单数据**：来自配置的供应商查询接口，与 Codex 任务观察连接独立。

## 快速开始

### 1. 系统要求

- 运行目标：macOS 13 或以上。当前构建和测试环境为 **macOS 26.2 / Apple Silicon**，尚未验证旧系统和 Intel Mac。
- 从源码构建：完整 **Xcode 16 或更新版本**，Swift 6 工具链。当前验证使用 **Xcode 26.6 / Swift 6.3.3**。
- 不需要 Homebrew、Node.js、第三方 Swift 包或 API key 即可构建并体验事件演示。
- 标准集成测试的模拟服务器使用 Xcode 提供的 `/usr/bin/python3`，应用运行本身不依赖 Python。

### 2. 从源码构建

下载或克隆 CodePulse 仓库后，在项目目录执行（已有本地目录可能仍名为 `codex-signal`）：

```bash
cd /你的项目路径/CodePulse
bash scripts/test.sh
bash scripts/build-app.sh
```

脚本优先识别 `/Applications/Xcode.app`，也支持 `~/Downloads/Xcode.app`。不修改系统全局开发者路径。自定义安装位置可显式指定：

```bash
DEVELOPER_DIR=/你的路径/Xcode.app/Contents/Developer bash scripts/test.sh
```

产物：

```text
dist/
├── Codex Signal.app
├── signalctl
├── README.md
├── docs/
├── examples/
└── Codex-Signal-0.1.0-arm64.zip
```

ZIP 内包含应用、CLI、README、文档和示例。名称中的架构取决于构建机器。当前包是本机架构构建，不是 Universal Binary。

### 3. 打开应用

```bash
open "dist/Codex Signal.app"
```

也可将应用复制到自己的“应用程序”目录。首次运行会显示详情窗口和菜单栏，自动尝试连接 Desktop，并显示本地历史。收到实时状态后菜单栏更新任务数；默认**不控制键盘 LED、不发出账单查询**。

本地包使用 ad-hoc 签名，尚未使用 Developer ID 签名或 Apple 公证。它适合本机开发测试，不是正式分发安装包。签名验证通过不代表公证或硬件兼容性通过。

### 4. 体验状态变化

保持应用运行，在项目目录执行：

```bash
./dist/signalctl demo
```

八秒演示依次发送：运行 → 等待审批 → 审批解决 → 完成。每个阶段约两秒，菜单栏和任务页会随之更新。如果你在设置中启用并保存了 LED，演示也会操作 LED。

演示只验证本地事件链路，**不能证明 Desktop 真实任务已经接入**。

## 状态灯如何工作

| 任务状态 | LED | 判断依据 |
| --- | --- | --- |
| 工作中、自动批准后继续执行 | 常亮 | 任务开始／继续事件或 active 快照 |
| 临时网络重试 | 常亮 | `willRetry: true` |
| 等待用户审批 | 快闪 | 结构化审批请求或等待审批状态 |
| 等待结构化输入 | 快闪 | 结构化输入请求或等待输入状态 |
| 额度／网络／权限等导致任务终止 | 快闪 | 明确终止错误，非单次工具失败 |
| 工作中观察连接断开 | 快闪 | 控制进程断开或健康检查失败 |
| 完成、取消、空闲 | 关闭 | 明确完成／取消或可确认的空闲状态 |
| 首次启动时状态未知 | 关闭，界面显示未知 | 不从陈旧历史伪造运行状态 |

### 多任务规则

只要有一个未解决的 attention，LED 就快闪；否则任意任务工作／重试时常亮；其余关闭。设置中的“项目过滤”可限制实时列表和 LED 聚合范围。

一个任务可同时有多个审批或输入请求。解决其中一个不会抹掉其他请求。已知请求 ID 的解决事件被收到后，会立即重新计算目标灯号；若没有其他等待事项，恢复常亮。应用事件收件箱约每 100 ms 扫描一次。

如果连接时只有等待状态快照、没有原始请求 ID，就需要下一次权威状态更新才能确认等待结束；本版不承诺所有接入方式都能零延迟恢复。

终止错误会保持 attention，普通 idle 快照不会静默覆盖它。点击“已知晓”可以清除该异常的灯光提示，但不会恢复任务或批准任何动作。明确的新任务执行、恢复或结束事件按状态规则更新。正在等待审批／输入的事项不能通过“已知晓”绕过。

### LED 的使用边界

- 默认每 **250 ms 翻转一次**，约每秒两个完整亮灭周期；可在设置调整。
- 仅使用 IOKit/HID 的内置键盘 Caps Lock **LED Output 元素**。
- 先枚举带 `Built-In` 标记的键盘和 LED Output，再用 `IOHIDDeviceOpen` 单独打开目标；不会先打开整个 HID 管理器。
- 不发送按键，不重映射 Caps Lock，不修改大小写锁定状态，不改变 Codex 审批策略。
- 灯被用于任务状态时，**不再代表真实 Caps Lock 状态**；实际 Caps Lock 按键仍然正常工作。
- 关闭 LED、正常退出或系统睡眠时，尝试读取当下 Caps Lock 状态并恢复灯；唤醒后重新连接设备。
- 写入失败会停止持续重试，菜单栏仍可使用；修复权限或设备状态后点击“保存设置／重试 LED”。
- 强制结束进程或系统异常退出无法保证恢复 LED。当前没有独立 watchdog。
- 当前仅选择内置键盘，不承诺支持外接键盘、所有 MacBook 型号或与其他控灯软件并存。

### 独立验证 MacBook LED

先在应用窗口点击“退出”，然后在普通终端执行：

```bash
cd /你的项目路径/CodePulse
./dist/signalctl led-test
```

请在测试期间观察 Caps Lock 指示灯，并暂时不要按 Caps Lock。约 11 秒的顺序为：

**熄灭 2 秒 → 常亮 3 秒 → 每 250 ms 翻转、快闪 4 秒 → 熄灭 2 秒 → 恢复系统状态。**

自检会拒绝与正在运行的 Codex Signal 应用同时控灯，记录设备名、HID 错误码、LED 报告值，并每 50 ms 左右采样一次 Caps Lock 逻辑状态。检测到逻辑状态变化即停止。Ctrl+C／SIGTERM 会触发受控退出并尝试恢复灯；SIGKILL 或系统崩溃不保证恢复。

`PASS` 只表示软件写入、恢复调用成功且采样未发现逻辑状态变化，**不代表已经肉眼确认实际发光**。HID 读回值也不能代替物理灯光验证。

**本机验收已通过：** 用户在普通终端运行更新后的 `dist/signalctl led-test`，成功识别 `Apple Internal Keyboard / Trackpad`；19 次序列写入及恢复写入成功，LED 报告值从 0 变为 1，Caps Lock 逻辑状态开始和结束均为 OFF，采样期间未发现变化。用户同时确认“目测运行结果是正常的”。这验证了本机 CLI 的实际常亮、快闪、熄灭及正常退出恢复；应用进程的权限、睡眠恢复和其他设备仍需单独验证。

**后续应用验证：** 在“能看到任务运行但灯不亮”的应用权限排查后，用户进一步确认“led 的测试成功了”。因此本机应用控灯也已确认可用；这不替代睡眠唤醒、全部任务生命周期及其他设备的验收。

此前 Codex 受限终端曾在管理器打开或 LED 元素枚举阶段失败，出沙箱测试也曾被审批服务 503 阻断。普通终端的成功结果确认了本机硬件可用，但没有单独确定此前失败的具体权限原因。完整过程见 [验证报告](docs/validation.md)。

### LED 的系统权限与排查

主界面分别显示“目标灯号”和“LED 硬件”状态。任务运行中只说明目标为常亮；若实际访问或写入失败，主界面会显示完整错误、当前应用路径、“重试 LED”和“打开输入监控设置”入口。打开系统设置不会自动授权。

如果 `signalctl led-test` 能正常亮灯而应用不能，先检查应用显示的错误；CLI 与 `.app` 的授权身份可能不同。确认授权的是主界面列出的应用副本，并退出重启后再验证。一次写入失败后应用会暂停控灯，修复权限后可以点击“重试 LED”，无需修改其他设置。

参考项目明确要求给实际控灯的程序授予“输入监控”。即使程序只写 LED，访问键盘 HID 仍可能被 macOS 权限或调用进程的沙箱拒绝。遇到 `0xe00002e2` 时：

1. 退出 Codex Signal 和其他控灯程序，避免多个程序交替写入同一盏灯。
2. 打开 **系统设置 → 隐私与安全性 → 输入监控**，检查实际运行程序的授权。
3. 测试本项目 CLI 时，对应可执行文件为项目目录下的 `dist/signalctl`。添加文件时可用 `Command-Shift-G` 输入实际完整路径；若系统把权限归属到终端应用，以系统实际显示的应用为准。
4. 使用菜单栏应用时，对应项目目录下当前构建的 `dist/Codex Signal.app`；若已复制到“应用程序”，应授权实际启动的那个副本。CLI 成功不等于应用也已获得权限。
5. 按系统提示退出并重新启动对应程序，再在普通终端运行上面的 `led-test`。重新构建 ad-hoc 签名程序后，可能需要重新授权。

仍然失败时，请记录完整错误码和失败阶段。Karabiner 等软件的独占访问、系统持续改写灯状态也可能影响结果；先检查现有配置，不要运行参考项目的旧键位映射脚本。无需因测试失败直接使用 `sudo`、修改 Caps Lock 映射或关闭系统保护。输入监控由用户在系统设置中授予，本项目不会自动修改权限。

## 连接 Codex 任务

### 方式 A：自动连接 Codex Desktop（默认）

旧版在 app-server 地址为空时不启动观察，因此会一直显示“实时观察未连接”。新版把空地址解释为自动连接 Desktop；无需手动启动 app-server。

1. 保持 Codex Desktop 正在运行。
2. 在 Codex Signal 的“设置 → Codex 观察”确认数据目录，默认为当前用户主目录下的 `.codex`。
3. **高级 app-server socket 路径留空**，点击“保存并连接”。正常启动应用时也会自动连接。
4. 观察任务页的连接诊断：连接中 → IPC 已连接、发现任务 → 已确认任务数量。仅完成握手不代表已经收到任务状态。

应用连接数据目录下的 `ipc/ipc.sock`，通过 Desktop 的本地订阅协议获取任务状态。每 5 秒从只读数据库发现最近 100 个未归档、非内部子任务的 ID 和显示元数据；数据库中的“进行中”状态不会驱动 LED。首次发现范围之外、未载入 Desktop、其他主机上的任务可能不可见；已确认仍在运行的任务不会仅因离开最近列表就取消订阅。

“候选／待响应”包含数据库发现但 Desktop 尚未返回快照的历史任务，不等于这些任务正在运行，也不会单独触发 LED 告警。本机普通终端已完成握手并收到 2 个任务的状态，其中当前任务被确认为“运行中”。

实时状态来自 `threadRuntimeStatus` 和结构化 `requests`：运行时常亮，已识别的审批／输入请求快闪，请求移除后恢复常亮，idle 关闭，systemError 告警。任务 owner 断开、IPC 断开或补丁序号缺失时，原有活跃任务进入观察故障状态并重连／重订阅。普通聊天内容不会触发审批提示。Desktop 分支目前依赖运行时错误状态；未暴露为 systemError 的终止错误仍需补充覆盖验证。

此适配使用本机客户端及 Mac-Agent-Beacon 源码确认的**私有状态协议 v11**，不是稳定的官方扩展接口。协议变化、消息超过 32 MiB、权限拒绝或任务发现失败都会显示诊断。快照可能携带对话内容；程序只保留状态投影，不记录或持久化原始 IPC 消息。

独立检查连接（不操作 LED，不投递演示事件，可与应用同时运行）：

```bash
./dist/signalctl desktop-check 12
```

可加第二个参数指定 Codex 数据目录。程序在 1～60 秒内收集状态，打印连接阶段和已确认任务数；没有确认状态时返回非零退出码。若在 Codex 受限终端出现 `Operation not permitted`，需要在普通终端复核，不能据此判断 Desktop 没有任务。

### 方式 B：已有 app-server 的只读观察（高级）

在“设置 → Codex 观察”填写：

1. 有效的 Codex 可执行文件路径。
2. **已有** app-server 的 Unix socket 路径。
3. 点击“保存并连接”。

本机曾检测到的 Desktop 内置 CLI 路径为：

```text
/Applications/ChatGPT.app/Contents/Resources/codex
```

不同安装版本可能不同，请以本机实际文件为准。程序调用：

```text
codex app-server proxy --sock <你配置的已有 socket>
```

仅发送初始化、已加载任务列表和元数据读取请求，接收结构化通知。**不会启动新服务器、创建／恢复任务、回复审批请求或修改审批策略。**

它能看到的是该服务器承载的任务；“连接成功”不意味着当前 Desktop 的任务一定属于同一个服务器。当前机器调研时没有发现可用的 app-server 控制 socket。不要将 `.codex/ipc/ipc.sock` 填到此处：它使用另一套带二进制长度头的协议，已由默认 Desktop 观察器单独处理。

行为：

- 接收到通知时直接更新。
- 约每 2 秒读取已加载任务和状态，弥补未收到通知的情况。
- 只应用未被更新通知取代的在途快照，隔离旧连接的迟到回调。
- 查询超过 12 秒未回应视为观察故障；已有活动任务进入 attention。
- 连接运行中失败后约 5 秒尝试重连；缺失路径或首次启动配置错误需要修正并重新连接。
- 这是通知加轮询的预览实现，没有得到上游订阅水位线保证，不能宣称绝不丢失瞬时事件。

### 方式 C：CLI／hook 事件入口

`signalctl emit` 提供跨 Desktop／CLI 共用的归一化事件入口。它**不是已经安装好的 Codex hook**。只有核实所用 Codex 版本的真实 hook 名称及 payload 后，才应编写转接器。

```bash
./dist/signalctl emit my-observer task-1 started \
  --turn turn-1 --title "构建项目" --project /path/to/project

./dist/signalctl emit my-observer task-1 approvalRequested \
  --turn turn-1 --request approval-1

./dist/signalctl emit my-observer task-1 requestResolved \
  --turn turn-1 --request approval-1

./dist/signalctl emit my-observer task-1 completed --turn turn-1
```

`SOURCE` 标识观察来源；同一个任务的事件必须使用一致的来源、任务 ID、turn ID。不同独立接入源没有统一上游身份映射时，不要重复接入同一任务，否则会出现两条记录。

支持的事件种类：

```text
started retrying approvalRequested inputRequested requestResolved
failed completed cancelled disconnected snapshot heartbeat
```

`approvalRequested`、`inputRequested` 和 `requestResolved` 必须提供 `--request`；`snapshot` 必须提供 `--phase`。详见 `./dist/signalctl --help`。

### 方式 C：JSON-RPC 流桥接

```bash
你的结构化事件输出程序 | ./dist/signalctl bridge my-observer
```

桥接接收一行一个 JSON-RPC 对象，只映射已支持的方法，不解析聊天文本。输入流必须本身包含 Codex app-server 协议通知／请求；普通 CLI 文本、任意日志或 `codex exec --json` 输出不保证兼容。

桥接存活时每 5 秒投递一次心跳，EOF 投递断线事件。应用收不到心跳超过 15 秒时，将该源的活动任务标为观察断线。**桥接心跳只证明桥接进程存活，不证明其上游连接健康**；上游程序必须在连接失效时关闭流或提供相应事件。

单次 `emit` 默认不建立长期健康租约。只发送 started 却永远不发送完成事件，会留下工作状态；应用不会因为长时间无 token 输出而猜测失败。

### 只读本地历史

历史模式默认读取 `~/.codex/state_5.sqlite` 和可选的 `thread_history_1.sqlite`：显示最近 30 条非归档任务的标题、工作目录、累计 token 记录和最近 turn 状态，每 10 秒刷新。优先使用用户设置的任务名，展示标题最长 160 字符；有来源字段时过滤内部 subagent／审批任务。

数据库以只读方式打开，不扫描 prompt、工具输出或代码正文。SQLite schema 是版本相关的本地兼容方案，不是稳定公共 API。遇到结构不兼容会显示错误。

即使数据库写着 `inProgress`，也只显示“实时状态未确认”。**历史列表不会触发常亮或快闪，也不能用于判断审批等待。**

## 配置用量与余额

### 连接 PackyCode 账户余额

新版有专用 PackyCode 配置，不需要手填字段路径。升级时先退出旧版，再打开 `dist/Codex Signal.app`；已有 LED、历史和观察设置会保留，已配置的自定义查询不会被强制改成 PackyCode。

1. 打开“设置 → 余额与用量”，数据来源选择 **PackyCode 账户余额**。
2. 选择你实际登录的控制台域名：`https://www.packyapi.com` 或 `https://www.packyapi.ai`。这两个域名不会自动互相尝试，也不会跟随重定向转发令牌。`.com` 来自 All API Hub 指南；`.ai` 是用户提供的实际站点，其账户接口兼容性仍需实测。
3. 填写该账号的数字 **用户 ID**，以及可选的账户显示名。
4. 在安全输入框粘贴 **账户访问令牌**，不带 `Bearer ` 前缀。这是账号管理凭据，**不是用于 `/v1/responses` 的模型调用 API Key**。
5. 点击 **“保存配置与令牌并查询”**。配置写入本地设置，令牌仅存 macOS Keychain，随后查询。
6. 打开“用量”页，核对余额、USD 单位、查询来源和最后成功更新时间，并与同一账号的控制台比较。

**如何取得用户 ID 和账户令牌？** 若已用 All API Hub 添加这个 PackyCode 账号，进入其账号编辑页，核对网站 URL、用户 ID 和访问令牌，只把必要字段填入本地 Codex Signal。若尚未添加，可按 [All API Hub 的 PackyCode 指南](https://github.com/qixing-jk/all-api-hub/blob/6f55c631e37d2864799e297dde02f07d3f504a89/docs/docs/service-guides/packycode.md)在浏览器登录后添加账号。不同版本的字段位置可能不同；不要把导出备份、API Key 列表或含凭据的截图发到聊天。

All API Hub 的自动添加流程可能在账户访问令牌不存在时生成令牌，应先阅读其操作提示。Codex Signal 本身只读余额，不生成或轮换账户令牌，不读取密钥列表，不访问浏览器 Cookie。

### 接口与金额口径

源码依据：[All API Hub](https://github.com/qixing-jk/all-api-hub/tree/6f55c631e37d2864799e297dde02f07d3f504a89) 的 PackyCode 指南截图将其识别为 `new-api`；共用账户 service 使用以下协议。它是**源码确认的兼容接口**，不是已经从 Packy 官方公开账单文档确认的稳定契约。

| 项目 | 实现 |
| --- | --- |
| 请求 | `GET <所选控制台域名>/api/user/self`；无 query、无 body |
| 认证 | `Authorization: Bearer <账户访问令牌>`、`New-API-User: <数字用户 ID>` |
| 业务成功 | HTTP 200 且 `success: true`；有非零业务 code 时拒绝 |
| 账号核对 | 响应 `data.id` 必须与填写的用户 ID 一致 |
| 余额 | `data.quota / 500000`，按 All API Hub 的 New API 口径显示 USD |
| 凭据隔离 | 钥匙串按提供商、所选地址和用户 ID 分开保存 |

菜单栏和用量页最多显示 6 位小数，保留小额余额。缺失、null、布尔值或无效余额报错；真实 0 与负数可以显示。不会用历史 token 数估算真实余额，也不会自动按固定汇率转换人民币。

**本次先提供余额。** 账户接口没有经过核实的套餐周期总额，因此不把余额与累计消费相加来制造使用比例，也不承诺日额度、重置时间、项目消费或价格查询。若控制台显示人民币、赠送额度或套餐值，应先核对口径，不能只比较页面上的数字。

首次账号请求、真实币种口径及钥匙串交互需要用户在本地验收。接口变化或账号认证方式不兼容时会报错；目前不自动登录、刷新短期登录 token 或读取浏览器会话。详细源码证据见 [PackyCode 接入记录](docs/packy-integration.md)。

### 配置已确认的查询接口

如果使用其他已确认接口，在“设置 → 余额与用量”选择 **自定义 JSON 接口**。原有高级字段仍然可用，保存后生效：

| 设置 | 含义 |
| --- | --- |
| HTTPS GET 地址 | 已核实的只读 JSON 查询地址；不允许 URL 用户名、密码、查询参数或 fragment |
| 账户显示名 | 用于标识当前账户，默认 Packy Code |
| 余额字段 | 点分隔的嵌套 JSON 对象路径，例如 `data.balance` |
| 已用／总额字段 | 必须一起配置，单位和统计范围必须一致 |
| 币种或额度单位 | 如 `CNY`、`USD`、`credits`，不会自动当作人民币 |
| 单位换算除数 | 例如接口以分返回，除数填 `100`；原单位则填 `1` |
| 周期说明 | 例如“本月”；配置比例时必填，本版不自动推断重置时间 |
| 认证头 | `Authorization` 或 `X-API-Key` |
| 认证前缀 | Bearer 认证填 `Bearer `，注意末尾空格；其他认证按官方要求填写 |
| 刷新间隔 | 默认 60 秒，最少 30 秒，仍需遵守官方限制 |

在“新凭据”输入 token 后点击“保存凭据”。凭据按查询地址保存到 macOS Keychain，不写入 settings.json。请不要在聊天、截图或项目仓库中暴露密钥。

本版只支持对象字段路径，不支持数组索引、POST、自定义脚本、Cookie 登录和 URL 查询参数。若官方接口要求这些方式，需要新增专用适配器。

### 数值例子

下面是**自造演示数据，不是 Packy 官方响应格式**，文件见 `examples/usage-response.json`：

```json
{"data":{"balance":"12640","used":"3800","limit":"10000"}}
```

若三个字段映射为 `data.balance / data.used / data.limit`，除数 `100`，单位 `CNY`，周期“本月”，则显示余额 126.40 CNY、已用 38.00 CNY、总额 100.00 CNY、使用率 38%。

- `null` 表示未知，不转成零。
- 总额为零或未知时，不计算百分比。
- 超过额度可以显示大于 100% 的数字；进度条视觉上封顶。
- 不用累计充值额充当周期额度，也不通过余额差推算消费。
- 金额内部使用 `Decimal`；建议接口以十进制字符串提供精确金额。
- 菜单栏优先显示余额；仅有有效比例时显示百分比。展开面板可看全部字段。

### 刷新失败时

最后一次成功数据保留在内存中，并明确标记过期；重启后重新查询，不从磁盘恢复陈旧账单。

- 401／403：暂停自动查询，更新凭据或相关配置后恢复。
- PackyCode 返回业务拒绝或账号 ID 不匹配：暂停查询，不显示原始响应中的敏感内容；核对账号并重新保存凭据。
- 429：遵守 `Retry-After`（秒数或 HTTP 日期）。
- 5xx、断网、超时：退避重试，普通退避最长 30 分钟；服务端要求更长时遵守服务端。
- 不跟随重定向，不向其他地址转发凭据；响应上限 1 MB。
- 同一时间只发一个查询；手动刷新也遵守最小间隔和退避。
- 账单查询失败只影响用量显示，**不会直接改变任务 LED**。

## 设置与数据

编辑设置后点击“保存设置”生效。开启 LED 表示你接受它作为任务灯使用；改变菜单栏、项目过滤和刷新设置同样需保存。

默认应用数据目录：

```text
~/Library/Application Support/CodexSignal/
├── settings.json
├── app.lock
└── inbox/
```

- 数据目录权限为 `0700`；收件箱采用原子写入，避免读到半个事件。
- 事件文件超过 64 KB、格式错误或积压超过 30 秒时不进入状态核心，防止重启后重放旧活动任务。
- 消费后的事件文件删除；实时状态保存在内存中，重启后需要上游重新同步。
- 应用使用文件锁限制单实例，避免两个实例同时控制 LED。
- 不上传本地历史、提示词或代码。只有启用用量查询后，才向所配置地址发送查询和凭据。
- 不安装 root helper、系统扩展、登录项或 daemon。

开发测试可用环境变量指定独立数据目录：

```bash
CODEX_SIGNAL_HOME=/tmp/codex-signal-demo ./dist/signalctl paths
```

应用与 `signalctl` 必须使用相同的 `CODEX_SIGNAL_HOME` 才能通信。普通使用不需要设置此变量。

### 退出与卸载

在窗口右上角点击“退出”，以便执行 LED 释放。只关闭窗口不会退出后台应用。

卸载时先删除设置中保存的接口凭据，再退出应用、移除 `.app` 和上述应用数据目录。也可在“钥匙串访问”中查找服务名 `local.codex-signal.usage`，删除不再使用的地址条目。程序不会自动删除 Codex 的任何文件。

## 构建与测试

标准流程：

```bash
bash scripts/test.sh
bash scripts/build-app.sh
./dist/signalctl replay examples/lifecycle.jsonl
```

离线回放应输出 `LED: off`，不启动应用、不查询账单、不触碰键盘。

也可以在完整 Xcode 工具链下直接运行 `swift test`。项目使用 XCTest，不再使用自制测试框架。Xcode 可直接打开 `Package.swift` 查看和运行测试。

若处于 Codex 等已经受限的环境，SwiftPM 再创建内部子沙箱可能报 `sandbox_apply: Operation not permitted`。本项目提供针对 SwiftPM 子沙箱的构建选项：

```bash
SIGNAL_NESTED_SANDBOX=1 bash scripts/test.sh
SIGNAL_NESTED_SANDBOX=1 bash scripts/build-app.sh
```

此选项只给 SwiftPM 传递 `--disable-sandbox`；不会改变 Codex 的权限、审批策略或系统 SIP。普通终端不需要设置。缓存置于项目 `.build/cache` 和临时 Clang 缓存目录。

打包脚本构建 Release 二进制，生成 Info.plist，进行本地 ad-hoc 签名并验证，最后生成 ZIP。`dist/` 和 `.build/` 已加入 `.gitignore`。

## 架构与源码

```text
Codex Desktop ──本地 IPC 快照────┐
Codex app-server ──只读 JSON-RPC──┤
signalctl emit / bridge ──事件队列─┤
                                ▼
                         StateEngine
                                │
                        多任务聚合与项目过滤
                           ┌────┴────┐
                           ▼         ▼
                        菜单栏     LEDDriver

Codex SQLite ──只读元数据──→ 历史列表（不驱动 LED）
HTTPS JSON + Keychain ────→ 用量面板（独立刷新）
```

| 路径 | 职责 |
| --- | --- |
| `Sources/SignalCore/TaskState.swift` | 事件校验、请求集合、去重、turn 隔离、状态聚合 |
| `Sources/SignalCore/CodexAdapter.swift` | 已确认协议字段到内部事件的映射 |
| `Sources/SignalCore/DesktopState.swift` | Desktop 状态投影、事务化补丁、revision 校验与二进制分帧 |
| `Sources/SignalCore/Usage.swift` | 金额与字段映射、比例、JSON 行分帧 |
| `Sources/SignalCore/PackyAccount.swift` | PackyCode 请求、域名与用户 ID 校验、业务响应和 USD 换算 |
| `Sources/SignalMac/AppServerObserver.swift` | 现有服务器代理、通知、状态轮询、断线重连 |
| `Sources/SignalMac/DesktopObserver.swift` | Desktop IPC 自动连接、任务发现、订阅和 owner 断线处理 |
| `Sources/SignalMac/LEDDriver.swift` | 内置 HID LED 输出与释放 |
| `Sources/SignalMac/HistoryReader.swift` | 只读 SQLite 元数据访问 |
| `Sources/SignalMac/UsageClient.swift` | 钥匙串、HTTPS 查询、重定向拒绝、Retry-After |
| `Sources/SignalMac/Storage.swift` | 配置、收件箱、单实例锁 |
| `Sources/SignalApp/` | AppKit 菜单栏、SwiftUI 窗口、运行协调 |
| `Sources/SignalCLI/` | 事件投递、桥接、演示、离线回放工具 |
| `Tests/SignalCoreTests/` | 标准 XCTest 单元与本地集成测试 |

协议适配依据本机 Codex `0.154.0-alpha.6.2` 导出的 schema，不应假定所有 Codex 版本具有相同字段。设计文档保留了最初规划，**当前功能以本 README 和代码为准**：

- [开源项目调研](docs/research.md)
- [实现方案](docs/implementation-plan.md)
- [Packy 接入契约](docs/packy-integration.md)
- [方案 Review](docs/review.md)
- [503 诊断](docs/network-diagnosis.md)

## 故障排查

### `xcodebuild` 提示只有 Command Line Tools

确认完整 Xcode 已安装并打开过一次。项目脚本能发现默认位置的 Xcode；也可设置 `DEVELOPER_DIR` 指向实际安装位置，无需修改全局配置。移动 Xcode 后使用新路径重新运行脚本。

### 菜单栏显示 0，但历史列表有任务

这是预期的区分。历史记录不是实时运行证据。先用 `signalctl demo` 验证本地通道，再配置真正承载任务的观察源。

### 等待审批时没有闪灯

确认 LED 已启用并保存，且设置页没有 HID 写入错误。然后查看任务页是否真的收到了结构化等待状态。仅在聊天中看到“请确认”，或只启用了历史读取，不会闪灯。

### 显示“未找到可直接写入的内置 Caps Lock LED”

当前键盘可能未暴露匹配的 HID Output 元素，或系统不允许访问。查看设置页的状态／错误码；可继续使用菜单栏。不要通过模拟按键、修改大小写或关闭系统保护来绕过此限制。

### 观察连接成功，但没有 Desktop 任务

先确认使用的是新版应用，并让高级 app-server 路径留空，以启用 Desktop 自动观察。如果显示“IPC 已连接，尚未收到任务快照”，代表握手成功但任务 owner 尚未返回状态；确认数据目录属于当前 Desktop，在 Desktop 中打开目标任务，再用 `desktop-check` 检查。缺失 socket、权限失败和协议不兼容会分别显示，不会只停留在笼统的“未连接”。

如果主动配置了高级 app-server 路径，目标服务器可能与 Desktop 不是同一实例；此时清空路径并重新连接。程序不会自动创建服务器来冒充已接入 Desktop。

### 余额显示 `—` 或“响应缺少字段”

`—` 表示未知，不代表余额为零。PackyCode 模式下核对实际登录域名、数字用户 ID 和账户访问令牌；模型 API Key 不能替代账户令牌。自定义模式下核对字段路径、单位和认证方式。`examples/usage-response.json` 仅作演示，不能当作 Packy 官方接口定义。

### PackyCode 返回 401／403、302 或账号不匹配

401／403 先检查凭据类型、是否过期和用户 ID；在本地保存正确账户令牌后恢复查询。302 说明所选地址要求重定向，程序会拒绝转发凭据；请通过已登录的控制台或 All API Hub 核对域名，手动选择后重新保存该域名的令牌。账号不匹配时不更新余额。不要通过关闭 TLS 验证、粘贴 Cookie 或猜测多个域名来消除报错。

### 出现 Packy `gpt-5.6-luna` 无可用渠道的 503

之前这个错误来自 Codex 的自动审批服务调用，与本程序账单查询是两条独立链路。修改本程序设置不会修复 Codex 的审批模型路由。详见诊断文档。

### 关闭了菜单栏，找不到设置

重新打开同一个 `.app` 即可显示窗口。应用已经运行时不要再直接执行第二个二进制实例；单实例锁会拒绝它。

## 验证记录与后续工作

已在 Xcode 26.6 / Swift 6.3.3 / macOS 26.2 / arm64 环境运行 **44 项 XCTest：43 项通过、1 项因沙箱禁止 Unix socket 而跳过、0 失败**。用户另在普通终端验证了真实 Desktop 握手与当前任务状态。详见 [验证报告](docs/validation.md)：

- 多任务优先级、多个审批／输入请求、审批解决、临时重试与终止错误。
- 异常已知晓、快照覆盖、旧 turn／重复事件、观察断线和恢复。
- 普通文本／自动审批不误触发、毫秒级事件顺序、分片与大小限制。
- 小数精度、缺失字段、无总额、超额比例、无效查询配置。
- 私有事件队列、过期事件过滤、符号链接处理、单实例锁。
- 只读数据库、历史进行中不冒充实时、模拟 app-server 协议与 HTTP Retry-After。
- PackyCode 请求头、金额精度、业务失败、账号校验、域名与凭据隔离、旧配置迁移、模拟 HTTP 错误与响应大小上限。

这些测试没有使用真实 API 凭据，没有调用付费推理，也没有写入真实键盘 LED。

另外，用户已在普通终端完成真实 LED 自检并肉眼确认灯效正常：常亮、快闪、熄灭和正常退出恢复通过，采样期间 Caps Lock 逻辑状态保持 OFF。这是独立于上述 XCTest 的本机硬件验收。

发布前仍需完成：

1. 在本地输入 PackyCode 账户凭据，验收首次真实请求并与控制台核对币种和余额；源码适配和模拟测试已完成。
2. 在真实 Desktop 实例中确认全部任务、审批／输入解决和终止事件覆盖。
3. 验证应用退出与睡眠恢复，以及初始 Caps Lock 为 ON 时的恢复；本机应用控灯和 CLI 初始 OFF 的灯效、正常退出恢复已通过。
4. 全部 UI 交互检查、较长时间能耗和内存测试、旧 macOS／其他硬件兼容性验证。已成功启动预览应用并读取任务页；进一步自动点击及公开文档查询再次被审批服务 503 阻断。
5. 根据实际分发需求增加 Developer ID 签名、公证与更新流程。

本版没有自动安装 hooks、运行服务器健康检查、项目账单分摊、侧边浮窗或开机启动。这些是后续工作，不是隐藏在配置里的现成功能。
