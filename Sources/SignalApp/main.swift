import AppKit
import SwiftUI
import SignalCore
import SignalMac

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lock: InstanceLock?
    private let model = Model()
    private var item: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { lock = try InstanceLock() }
        catch {
            let alert = NSAlert(); alert.messageText = error.localizedDescription; alert.runModal()
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        model.changed = { [weak self] in self?.updateItem() }
        updateItem(); model.start(); showWindow()
    }
    private func updateItem() {
        if model.showMenu {
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item?.button?.target = self; item?.button?.action = #selector(showWindow)
            }
            item?.button?.title = model.menuTitle
            item?.button?.toolTip = "Codex Signal · 点击查看任务、余额与设置"
        } else if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
    }
    @objc func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Codex Signal"
            window.contentView = NSHostingView(rootView: Dashboard(model: model))
            window.isReleasedWhenClosed = false; window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

struct Dashboard: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.mode == .blink ? "exclamationmark.circle.fill" : "circle.fill")
                    .foregroundStyle(model.mode == .blink ? .orange : (model.mode == .solid ? .green : .secondary))
                VStack(alignment: .leading) {
                    Text("Codex Signal").font(.title2.bold())
                    Text("\(model.mode == .blink ? "需要处理" : model.mode == .solid ? "任务运行中" : "没有已确认的活动任务") · 目标灯号 \(model.mode.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.ledEnabled ? "LED 硬件：\(model.ledStatus)" : "LED 未启用")
                    .font(.caption).foregroundStyle(model.ledFailed ? .orange : .secondary)
                    .textSelection(.enabled)
                if model.ledFailed {
                    Text("任务状态正常不代表 LED 写入成功。若终端自检能亮，请检查当前应用的输入监控授权，授权后退出并重新打开应用。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("重试 LED") { model.retryLED() }
                        Button("打开输入监控设置") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    Text("当前应用：\(Bundle.main.bundleURL.path)").font(.caption2).textSelection(.enabled)
                }
            }
            TabView {
                tasks.tabItem { Label("任务", systemImage: "list.bullet.rectangle") }
                usage.tabItem { Label("用量", systemImage: "chart.bar") }
                settings.tabItem { Label("设置", systemImage: "gearshape") }
            }
            if !model.notice.isEmpty { Text(model.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(20).frame(minWidth: 680, minHeight: 550)
    }
    var tasks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.observerStatus).font(.callout).foregroundStyle(.secondary)
                if model.shownRecords.isEmpty {
                    Text("尚无实时事件。默认自动连接 Codex Desktop；请确认它已启动，并在设置中核对 Codex 数据目录。")
                        .padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary).cornerRadius(10)
                }
                ForEach(model.shownRecords) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title).fontWeight(.medium)
                            Text(row.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(row.phase.label) · \(row.source)\(row.acknowledged ? " · 已知晓" : "")").font(.caption)
                        }
                        Spacer()
                        if row.phase == .interrupted && !row.acknowledged {
                            Button("已知晓") { model.acknowledge(row.id) }
                        }
                        Text(row.updatedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                    }.padding(10).background(.quaternary).cornerRadius(8)
                }
                Divider()
                Text("最近的本地记录").font(.headline)
                Text(model.historyStatus).font(.caption).foregroundStyle(.secondary)
                ForEach(model.history) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).lineLimit(2)
                        Text("\(row.status) · 累计记录 \(row.tokens) tokens").font(.caption).foregroundStyle(.secondary)
                        Text(row.project).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 5)
                }
            }.padding(12)
        }
    }
    var usage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.usageProviderTitle).font(.title3.bold())
                Text(model.usageStatus).foregroundStyle(.secondary).textSelection(.enabled)
                if let data = model.lastUsage {
                    Text(data.account).font(.headline)
                    if let balance = data.balance {
                        Text("余额 \(model.money(balance, digits: 6)) \(data.unit)").font(.largeTitle.monospacedDigit())
                    }
                    if let ratio = data.ratio {
                        Text("\(data.period) · 已用 \(model.money(ratio * 100))%")
                        ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: ratio).doubleValue)))
                    }
                    if let used = data.used { Text("已用：\(model.money(used)) \(data.unit)") }
                    if let limit = data.limit { Text("总额：\(model.money(limit)) \(data.unit)") }
                    Text("最后成功更新：\(data.fetchedAt.formatted())").font(.caption)
                    Text("来源：\(data.origin)").font(.caption).textSelection(.enabled)
                } else {
                    Text("—").font(.system(size: 48, weight: .light))
                    Text("尚无已验证的账单数据。不会用本地 token 估算填充真实余额。")
                }
                Button(model.refreshing ? "正在刷新…" : "刷新（遵守最小间隔与退避）") { model.refreshUsage() }
                    .disabled(!model.preferences.usageEnabled || model.refreshing)
                Link("打开 Packy 官方文档", destination: URL(string: "https://docs.packyapi.ai/")!)
                if model.isPackyUsage {
                    Text("在设置中选择实际登录的控制台域名，填写用户 ID 和账户访问令牌。余额以 USD 显示；账户余额不代表套餐总额，因此不生成使用百分比。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("接口依据 All API Hub 的 New API 适配；首次连接请与 PackyCode 控制台余额核对。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("按已保存的 HTTPS JSON 字段映射查询。未知或无效金额显示错误，不替换为零。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var settings: some View {
        ScrollView {
            Form {
                Section("显示方式") {
                    Toggle("顶部菜单栏", isOn: $model.preferences.showMenu)
                    Toggle("Caps Lock LED", isOn: $model.preferences.ledEnabled)
                    Text("\(model.ledStatus)。只控制 LED；开启时灯不再代表 Caps Lock 大小写状态。关闭后恢复系统灯状态。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("项目过滤（路径包含，可留空）", text: $model.preferences.projectFilter)
                    HStack {
                        Text("快闪翻转间隔")
                        Slider(value: $model.preferences.blinkInterval, in: 0.1...1, step: 0.05)
                        Text(String(format: "%.2f 秒", model.preferences.blinkInterval)).monospacedDigit()
                    }
                }
                Section("Codex 观察") {
                    Toggle("显示本地历史元数据（不驱动 LED）", isOn: $model.preferences.historyEnabled)
                    TextField("Codex 数据目录", text: $model.preferences.codexHome)
                    Text("默认从此目录的 ipc/ipc.sock 自动连接 Desktop；每 5 秒发现最近 100 个未归档任务，只用实时快照驱动 LED。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Codex 可执行文件", text: $model.preferences.codexBinary)
                    TextField("高级：app-server socket（留空自动连接 Desktop）", text: $model.preferences.codexSocket)
                    HStack {
                        Button("保存并连接") { if model.save() { model.connect() } }
                        Button("断开观察") { model.disconnect() }
                    }
                    Text("Desktop IPC 与 app-server 是不同协议，请勿把 ipc/ipc.sock 填入高级路径。不会启动服务器、恢复任务、接管审批或修改 Codex 设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("余额与用量") {
                    Picker("数据来源", selection: $model.preferences.selectedUsageProvider) {
                        ForEach(UsageProvider.allCases, id: \.self) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }.onChange(of: model.preferences.selectedUsageProvider) { _ in model.credential = "" }
                    Toggle("启用查询", isOn: $model.preferences.usageEnabled)
                    if model.preferences.selectedUsageProvider == .packyCode {
                        Picker("实际登录的控制台", selection: $model.preferences.packySettings.origin) {
                            ForEach(PackyAccount.origins, id: \.self) { origin in Text(origin).tag(origin) }
                        }.onChange(of: model.preferences.packySettings.origin) { _ in model.credential = "" }
                        TextField("用户 ID（数字）", text: $model.preferences.packySettings.userID)
                            .onChange(of: model.preferences.packySettings.userID) { _ in model.credential = "" }
                        TextField("账户显示名", text: $model.preferences.packySettings.label)
                        Text("填写账户访问令牌，不是模型调用 API Key。可从已添加该账号的 All API Hub 账号编辑页核对用户 ID 和访问令牌；仅在此处输入，不要发到聊天。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("余额按 New API 的 500,000 quota = 1 USD 换算。请选择账号所在域名，程序不会跨域尝试其他站点。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("HTTPS GET 地址（无查询参数）", text: $model.preferences.usage.endpoint)
                        TextField("账户显示名", text: $model.preferences.usage.accountLabel)
                        TextField("余额字段，例如 data.balance", text: $model.preferences.usage.balancePath)
                        TextField("已用字段（可选）", text: $model.preferences.usage.usedPath)
                        TextField("总额字段（与已用一起配置）", text: $model.preferences.usage.limitPath)
                        TextField("币种或额度单位", text: $model.preferences.usage.unit)
                        TextField("单位换算除数，例如 100", text: $model.preferences.usage.scale)
                        TextField("周期说明，例如 本月", text: $model.preferences.usage.periodLabel)
                        Picker("认证头", selection: $model.preferences.usage.authHeader) {
                            Text("Authorization").tag("Authorization"); Text("X-API-Key").tag("X-API-Key")
                        }
                        TextField("认证前缀（Bearer 后需空格）", text: $model.preferences.usage.authPrefix)
                    }
                    SecureField(model.preferences.selectedUsageProvider == .packyCode ? "账户访问令牌（不含 Bearer）" : "新凭据（只存钥匙串）", text: $model.credential)
                    HStack {
                        Button("保存凭据") { model.saveCredential() }
                        Button("删除所选账号凭据") { model.deleteCredential() }
                    }
                    TextField("刷新秒数（最少 30）", value: $model.preferences.refreshInterval, format: .number)
                    Button("保存配置与令牌并查询") { model.connectUsage() }.buttonStyle(.borderedProminent)
                }
                Button("保存设置／重试 LED") { model.save() }.buttonStyle(.borderedProminent)
                Text("关闭菜单栏后，重新打开应用即可进入此设置。数据仅保存在本机。")
                    .font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).padding(10)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
