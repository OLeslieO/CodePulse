# 0.1.0 验证报告

日期：2026-09-18。此报告区分自动测试、产物检查与未完成的外部集成验证。

## 当前外观：半透明银白玻璃

按用户最新要求，弹窗与详情窗口统一切换为浅色 Aqua 外观及银白玻璃材质，详情窗口移除不透明黑色底层。正文与次级文字使用深灰色；交互文字、状态和进度使用深青色，LED 灯点与环境光保留原青色。减少透明度／增强对比度时使用不透明银白底色。此轮 Release 编译和签名检查通过，实机材质效果仍待视觉验收。下文的深色描述为此前迭代记录。

## Pulse 界面更新（2026-09-19）

- 菜单栏新增 352px 原生弹窗，使用深色毛玻璃、青色活动光、任务时间线、余额及八点 LED 指示；详细任务、用量和设置继续使用独立窗口。
- 增加纯展示用途的连续观察计时，不修改 StateEngine、Desktop 协议、LED 驱动、账户认证或余额换算逻辑。
- 本轮 XCTest：44 项，43 项通过、1 项 Unix socket 集成测试受沙箱限制跳过、0 失败。Debug 和 Release 编译通过，Release 包的 ad-hoc 签名验证通过。
- 已实现减少动态效果、减少透明度、增强对比度的界面分支，以及图标按钮辅助功能名称。macOS 14 及以上启用余额数字过渡，macOS 13 使用静态数字。
- 尝试创建独立原生预览时，自动审批服务因 `gpt-5.6-luna` 渠道不可用返回 503，未完成截图或实际界面操作。编译与测试结果不能替代视觉验收。
- 实机待检查：菜单栏点击开关、Escape／点击外部关闭、列表滚动、齿轮跳转、关闭菜单栏后的设置入口、实际桌面背景下的玻璃观感，以及 VoiceOver／系统辅助显示选项。余额进度仅在接口提供总额时显示；真实 PackyCode 数据仍需账号对账。

### 原生 Liquid Glass 跟进

- macOS 26 分支使用 SwiftUI `glassEffect` 与 `.glass` 圆形按钮；以运行时版本判断保留 macOS 13–15 的 `NSVisualEffectView` 路径。源码构建要求更新为 Xcode 26 及 macOS 26 SDK。
- 降低黑色遮罩强度、收敛青色环境光，提高次级文字对比度；详情窗口使用胶囊式导航。减少透明度或增强对比度时使用不透明底色。
- 此轮通过 Release 编译与打包脚本的签名校验；脚本自动使用 `~/Downloads/Xcode.app`，未修改系统开发者目录。
- 用户请求的 `ibelick/ui-skills` 尚未安装：读取 GitHub 仓库目录被自动审批服务以相同的 Luna 渠道 503 拒绝，未取得技能正文；此轮不能声称已按该技能审核。后续需取得源码、完成安装后再核对技能要求。

### UI Skills 本地规范复核

- 用户随后下载了 `ibelick/ui-skills`，阅读版本为 `d07392a5db35940e0aa1cae637585ecd550c924f`。本轮采用其中的 `baseline-ui`、`fixing-accessibility`、`fixing-motion-performance`；HTML、Tailwind 和 React 专属规则不替换现有 SwiftUI 技术栈，用户明确要求的玻璃、环境光和微动画继续保留。
- 调整：移除手动字距和兼容材质的渐变描边；进度条由宽度动画改为缩放；光晕改为固定绘制后调整透明度；任务列表使用延迟布局，指示器离开视图时暂停；空任务入口改为“检查 Codex 连接”；余额错误摘要就地显示；导航改用原生分段 Picker；删除凭据使用系统确认框。
- 此轮 Release 编译、ad-hoc 签名验证通过。仍未完成真实玻璃效果、键盘操作、VoiceOver 与动效帧率的实机验收，不把静态规则检查表述为这些项目已通过。
- 技能正文已读取并用于本轮工作，但安装到 `~/.codex/skills` 的本地复制请求仍被自动审批服务以 Luna 渠道 503 拒绝。因此全局技能安装状态仍为待完成；项目运行和构建不依赖技能目录。

后续安装确认：用户完成本地复制后，已逐一核对全部 7 个技能的 `SKILL.md`，与下载源码一致，且已出现在 Codex 可用技能列表中。上述安装阻塞已由用户手动完成安装解除。

### 视觉细化

- 弹窗和详情页统一品牌标题、分区标题与任务时间线；详情页保留状态来源、确认时间及异常确认按钮。待处理任务优先展示。
- 余额主数字与单位采用独立字号层级；八点 LED 预览放入低对比硬件指示条。正常 LED 诊断不再占据详情页顶部，失败时仍显示完整诊断及修复入口。
- 使用原生 Form 滚动，移除设置页重复滚动容器。弹窗按菜单栏所在屏幕的可用高度约束，内容过高时采用滚动布局。
- 原有 API、钥匙串、LED 驱动与状态判定未修改；真实屏幕下的材质、紧凑布局及键盘交互仍需实机视觉验收。

## 环境

- macOS 26.2，Apple Silicon / arm64。
- Xcode 26.6（17F113），安装位置 `/Applications/Xcode.app`。
- Swift 6.3.3，Swift Package Manager，XCTest。
- 没有下载第三方 Swift 依赖；应用依赖系统 AppKit、SwiftUI、IOKit、Security、SQLite。
- Codex 执行环境限制了用户级 SwiftPM 缓存及嵌套 sandbox-exec。验证使用项目缓存，并设置 `SIGNAL_NESTED_SANDBOX=1`，只关闭 SwiftPM 内部子沙箱；Codex 外层权限与审批策略未改变。

## 自动化测试

命令：

```bash
SIGNAL_NESTED_SANDBOX=1 bash scripts/test.sh
```

当前 XCTest：**44 项测试，43 项通过、1 项跳过、0 失败**。新增 Packy 测试 10 项通过；Desktop 的真实 Unix socket fixture 在 Codex 沙箱禁止绑定 socket 时明确跳过，普通终端可运行完整测试。

| 测试组 | 数量 | 覆盖范围 |
| --- | --- | --- |
| StateTests | 13 | 多任务、多个请求、重试、终止错误、已知晓、断线、快照、旧 turn、重复事件、文本忽略、时间精度、分帧 |
| UsageTests | 4 | Decimal 金额、超额比例、null／缺失／非法字段、查询地址与配置校验 |
| IntegrationTests | 8 | 原子事件收件箱、过期过滤、符号链接、目录权限、单实例、配置、只读 SQLite、内部任务过滤、模拟 app-server、Retry-After |
| DesktopTests | 9 | 结构化审批／输入、请求移除恢复、并发请求、旧 revision、缺失补丁、事务回滚、二进制分帧、缺失 socket、真实 Unix 传输 fixture（沙箱内跳过） |
| PackyTests | 10 | 请求方法和认证头、金额换算、缺失／非法金额、业务错误、账户身份、域名约束、凭据隔离、旧配置迁移、模拟 HTTP 状态／大小限制 |

测试运行器还可能输出 Swift Testing 的“0 tests”；项目实际使用 XCTest，以 `Executed 44 tests, with 1 test skipped and 0 failures` 为准。

集成测试服务器为本地模拟器，不连接真实 Desktop、不回复任何审批、不使用真实 API 凭据。SQLite 测试使用临时数据库，未修改用户的 Codex 数据。

## 构建与产物

命令：

```bash
SIGNAL_NESTED_SANDBOX=1 bash scripts/build-app.sh
```

产物位于 `dist/`：

- `Codex Signal.app`：原生 Release 应用。
- `signalctl`：独立事件／回放／历史工具。
- `README.md`、`docs/`、`examples/`：随包文档与离线示例。
- `Codex-Signal-0.1.0-arm64.zip`：应用、CLI 和文档的组合包。

检查项目：Mach-O arm64 架构、Info.plist 语法、ad-hoc 签名校验、ZIP 完整性、CLI 帮助以及 `examples/lifecycle.jsonl` 回放。回放预期为 `LED: off`、示例任务“已结束”。

ad-hoc 签名只验证本地产物一致性，没有 Developer ID 签名／Apple 公证，不是跨机器正式发布认证。

## 本机运行观察

- 已通过原生应用工具启动初次 Release 预览包。
- 已看到“Codex Signal”窗口、任务／用量／设置入口、空闲灯号和只读历史列表。
- 已运行打包 CLI 读取本机历史元数据；没有修改该数据库。
- 由首次界面检查发现内部审批任务和超长标题，随后修正并用回归测试验证；最终包包含修正。
- 后续点击用量页被自动审批服务 503 拒绝，因此没有声称全部设置交互或每个页面完成视觉 QA。

## 尚未通过的发布门槛

1. **真实 Desktop 完整状态覆盖**：新增 Desktop IPC 观察器已通过用户普通终端的握手和当前活跃任务状态验证；真实审批／输入解决、终止异常、睡眠恢复和应用到 LED 的完整链路仍待验收。
2. **Packy 真实账号对账**：已沿用户下载的 All API Hub 源码实现 New API 兼容余额适配，专用模拟测试通过；需要用户在本地保存账户令牌，验收实际接口、域名与余额币种口径。
3. **LED 恢复场景**：本机 CLI 的灯效、逻辑状态采样和正常退出恢复，以及后续应用控灯均已由用户确认通过；初始 Caps Lock 为 ON、睡眠恢复及中断退出仍待实机验证。
4. **真实 HTTP 认证与重定向行为**：实现已有拒绝重定向和钥匙串存储，模拟请求覆盖 HTTP 成功、302／401／403／429／503 和响应大小限制；未使用真实账户联网验收，URLSession 的实际重定向回调及钥匙串交互仍需实机确认。
5. **性能与平台**：没有完整能耗、长时间内存、旧系统、Intel／外接键盘兼容性测试。

结论：本地预览版可以交付用于本机体验和下一阶段接入验证；不能宣称完整覆盖所有原始集成目标或达到正式发布标准。

## LED 硬件尝试（2026-09-18）

- 用户已退出 Codex Signal，避免与自检同时控灯。
- I/O Registry 中存在内置 `Apple Internal Keyboard / Trackpad`，Keyboard usage 为 6、page 为 1。这仅证明设备被系统枚举，不证明 LED 写入可用。
- 已编译独立自检命令，计划执行熄灭、常亮、快闪和恢复，且持续检查 Caps Lock 逻辑状态。
- 实际执行 `signalctl led-test` 时，在打开 HID 管理器阶段得到：

```text
Caps Lock 逻辑状态（开始）：OFF
无法访问键盘 HID：-536870174 / 0xe00002e2
Caps Lock 逻辑状态（结束）：OFF
```

- `0xe00002e2` 对应当前 macOS SDK 的 `kIOReturnNotPermitted`。
- 未进入任何 LED 写入阶段，不能记录为“灯不亮”或“硬件不支持”。
- 申请出 Codex 沙箱进行相同测试时，自动审批服务返回 Packy `gpt-5.6-luna` 渠道不可用的 503，请求未执行。
- 当时下一步为用户在普通终端运行 `./dist/signalctl led-test` 并人工确认灯效；后续已完成，结果见末节。

## 参考源码后的驱动修订（2026-09-18）

已阅读用户下载的 Mac-Agent-Beacon，版本 `d18d652215bfb8f0ca20b532adffaecafa9987c5`。其 C helper 先枚举设备与 LED 元素，再单独打开目标键盘；README 明确要求手动授予 Input Monitoring。详细比较见 [调研记录](research.md)。

本项目 Swift 驱动已移除管理器级打开，在验证 `Built-In` 属性和 Caps Lock LED Output 后才执行 `IOHIDDeviceOpen`，释放时执行对应的 `IOHIDDeviceClose`。错误信息增加枚举到的键盘／内置键盘数量，用于区分设备不可见和输出元素不可见。没有安装参考项目、改键或修改系统授权。

最终修订通过 **25 项 XCTest，0 失败**。随后在同一 Codex 受限终端执行 Debug CLI 自检，实际输出：

```text
Caps Lock 逻辑状态（开始）：OFF
未找到可直接写入的内置 Caps Lock LED（枚举键盘 1，内置键盘 1）
Caps Lock 逻辑状态（结束）：OFF
错误：未找到可直接写入的内置 Caps Lock LED（枚举键盘 1，内置键盘 1）
```

该结果说明枚举到了一个带内置标记的键盘，但没有取得匹配的 LED Output 元素；尚未进入设备打开或写入阶段。仅凭这一结果不能区分权限限制与设备暴露的元素差异，不能宣称硬件已支持或不支持，也不能声称改动已经让灯亮起。本次没有再申请被阻断的出沙箱测试。

随后用户已在普通终端完成下述验收；应用进程的授权和睡眠／恢复效果需另行验证。

## 普通终端实机验收：通过

证据来源：用户提供运行日志，并确认“目测运行结果是正常的”。执行的是本项目打包后的 Release CLI：

```text
/Users/leslie/git/codex-signal/dist/signalctl led-test
Caps Lock 逻辑状态（开始）：OFF
设备：Apple Internal Keyboard / Trackpad
初始 LED 报告值：0（不等于肉眼验证）
现在开始：熄灭 2 秒 → 常亮 3 秒 → 快闪 4 秒 → 熄灭 2 秒
阶段 1：熄灭
阶段 2：常亮
亮灯后的 LED 报告值：1
阶段 3：快闪，每 250 ms 翻转一次
阶段 4：熄灭
已释放 LED，恢复系统状态
PASS：19 次序列写入及恢复写入成功，采样中未发现 Caps Lock 逻辑状态变化。物理灯效仍需人工确认。
Caps Lock 逻辑状态（结束）：OFF
```

| 验收项 | 结果与依据 |
| --- | --- |
| 目标设备访问 | 成功打开本机 Apple 内置键盘并写入 LED |
| 常亮、快闪、熄灭 | 软件调用成功，用户肉眼确认运行正常 |
| 灯值读回 | 初始为 0，亮灯后为 1，与写入目标一致 |
| Caps Lock 逻辑状态 | 开始／结束均 OFF，约 50 ms 间隔采样期间未发现变化 |
| 正常结束恢复 | 恢复写入成功，用户报告整体灯效正常 |

结论：**本机在普通终端运行 CLI 的 LED 硬件验收通过。** Codex 受限环境下的失败不能用来判定这台 MacBook 不支持 LED 控制；现有证据不足以单独归因于具体沙箱规则或某项系统授权。用户未提供授权操作细节，不据此假定授予了哪一个程序的权限。

此结果不覆盖菜单栏应用进程的独立授权、初始 Caps Lock 为 ON 时的恢复、Ctrl+C／SIGTERM 实机恢复、睡眠唤醒、长时间运行或其他型号。真实 Desktop 状态到 LED 的完整链路也仍待验收。

## 修复“实时观察未连接”：Desktop IPC

根因：用户已保存的 `codexSocket` 为空；旧版 `Model.start()` 仅在此字段非空时启动 app-server 观察，始终没有尝试连接 Desktop。历史列表来自 SQLite，与实时连接独立，所以能显示历史但不能反映真实运行状态。

改动：新增 `DesktopObserver` 和 `DesktopState`，空 app-server 地址默认连接所选 Codex 数据目录下的 `ipc/ipc.sock`。启动、保存连接设置、唤醒时使用同一连接选择逻辑；保留显式 app-server 模式。新增 `signalctl desktop-check`，可在不操作 LED 的情况下诊断连接。

协议依据：本地 Mac-Agent-Beacon `bin/codex-live.rb` 及当前 `/Applications/ChatGPT.app/Contents/Resources/app.asar` 的订阅方法和版本映射。状态消息为 v11，following 消息为 v1，4 字节小端长度头。只发送初始化、订阅和“不接管请求”的发现响应，不回答审批、不开始或恢复任务。

测试经过：最初传输 fixture 路径超过 Unix socket 长度上限，已改用短临时路径；随后确认 Codex 沙箱禁止 socket bind，测试改为仅在此权限错误发生时显式跳过，不隐藏其他失败。最终 34 项测试中 33 项通过，1 项跳过。该跳过项不计作已通过。

Codex 沙箱内的真实检查结果为 `Network.NWError error 1 - Operation not permitted`，未进入握手。用户随后在普通终端执行：

```text
/Users/leslie/git/codex-signal/.build/debug/signalctl desktop-check 12
正在连接 Codex Desktop 本地 IPC…
Desktop IPC 已连接，正在发现任务…
Desktop IPC 已连接，尚未收到任务快照（候选 19，待响应 19）
01a0aabd-cf9d-7a52-a4fe-14b24770426d：运行中
实时观察已连接 · Desktop · 已确认 1 个任务，待响应 18
实时观察已连接 · Desktop · 已确认 2 个任务，待响应 17
实时观察已连接 · Desktop · 已确认 2 个任务，待响应 17 · 部分任务正在重订阅
实时观察已停止
检查结束：收到 2 个任务的状态，2 个状态已确认；未操作 LED
```

**已验证：** 真实 Desktop 握手、订阅、快照解析，以及当前任务确实映射为运行中。剩余 17 个来自历史列表的候选没有返回快照，不能认定为活动任务或任务失败；最终代码已避免仅因这些候选未响应就显示“部分任务正在重订阅”的故障提示。

**验收边界：** 此次为 Debug CLI 的真实连接检查，菜单栏应用使用相同观察器，仍需退出旧版并启动更新后的应用确认界面与灯联动。私有协议可能随 Codex 升级变化，最近 100 个未归档任务之外的首次发现不保证覆盖，所有终止错误及完整生命周期尚未端到端验证。

## 后续应用 LED 验收：用户确认通过

用户先确认更新后的应用能检测任务运行，但灯未亮；设置页显示“未找到可直接写入的内置 Caps Lock LED（枚举键盘 1，内置键盘 1）”，重试后不变。应用未取得 LED Output 元素，尚未进入写入阶段。

随后新增主界面的“目标灯号／LED 硬件”独立显示、完整错误、当前应用路径、重试按钮和输入监控设置入口；Release 编译、签名和压缩包检查通过。引导用户为实际运行的 `.app` 检查系统输入监控授权并重启后，用户明确回复：**“led 的测试成功了！”**

据此记录本机应用控灯验证通过。用户没有提供这次的详细写入日志或全部操作步骤，不能额外推定已验证初始 Caps Lock 为 ON、睡眠唤醒、异常退出或所有状态转换。此前 CLI 的 19 次写入及恢复、逻辑 OFF 不变和肉眼验证记录仍独立保留。

## PackyCode 账户余额适配

源码证据：用户下载的 All API Hub，commit `6f55c631e37d2864799e297dde02f07d3f504a89`。其 PackyCode 指南截图使用 New API 类型，共用调用为 `GET /api/user/self`、Bearer 账户令牌、New-API-User 用户 ID，余额 quota 按 500,000 单位／USD 换算。详见 [接入记录](packy-integration.md)。

新增专用账户配置与钥匙串索引、固定只读请求、严格成功／账号／金额校验，沿用限流退避、旧响应隔离和拒绝重定向。老配置新增字段为可选，不会使既有 LED 设置和自定义查询设置因解码失败而重置。

PackyTests 共 10 项，使用虚构数据及自定义 URLProtocol，无真实网络、Cookie、账户令牌或付费请求。覆盖 1 quota = 0.000002 USD、负余额、真实零、缺失／布尔／畸形数值、业务失败、用户 ID 不匹配、域名限制、凭据索引隔离、原配置兼容、HTTP 错误与 1 MB 上限。44 项总测试中 43 项通过、1 项因 Unix socket 沙箱限制跳过、0 失败。

真实余额尚未查询。下一步由用户在本地设置中填写账号信息，点击“保存配置与令牌并查询”，核对控制台的同一账号、币种和余额。模拟测试成功不代表已完成这项验收。
