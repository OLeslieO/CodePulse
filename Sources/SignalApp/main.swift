import AppKit
import SwiftUI
import SignalCore
import SignalMac

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var lock: InstanceLock?
    private let model = Model()
    private var item: NSStatusItem?
    private var window: NSWindow?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { lock = try InstanceLock() }
        catch {
            let alert = NSAlert(); alert.messageText = error.localizedDescription; alert.runModal()
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        model.changed = { [weak self] in self?.updateItem() }
        updateItem(); model.start()
        if !model.showMenu { showWindow() }
    }
    private func updateItem() {
        if model.showMenu {
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item?.button?.target = self; item?.button?.action = #selector(togglePopover)
            }
            let symbol = model.mode == .blink ? "waveform.badge.exclamationmark" : "waveform.path"
            item?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: model.activityLabel)
                ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: model.activityLabel)
            item?.button?.image?.isTemplate = true
            item?.button?.imagePosition = .imageLeading
            item?.button?.title = model.activeCount > 0 ? " \(model.activeCount)" : ""
            item?.button?.alphaValue = model.mode == .off ? 0.6 : 1
            item?.button?.toolTip = "CodePulse · \(model.activityLabel) · 点击查看任务与余额"
        } else if let item {
            popover?.close()
            NSStatusBar.system.removeStatusItem(item); self.item = nil
            showWindow()
        }
    }
    @objc private func togglePopover() {
        guard let button = item?.button else { return }
        if popover?.isShown == true { popover?.performClose(nil); return }
        if popover == nil {
            let panel = NSPopover()
            panel.behavior = .transient
            panel.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.appearance = NSAppearance(named: .aqua)
            panel.delegate = self
            let availableHeight = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            let controller = NSHostingController(rootView: PulsePopover(model: model, maximumHeight: max(200, availableHeight - 40)) { [weak self] tab in
                self?.showDetails(tab)
            })
            controller.sizingOptions = [.preferredContentSize]
            panel.contentViewController = controller
            popover = panel
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover?.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController = nil
        popover = nil
    }
    private func showDetails(_ tab: DetailTab) {
        model.detailTab = tab
        popover?.performClose(nil)
        showWindow()
    }
    @objc func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "CodePulse"
            window.appearance = NSAppearance(named: .aqua)
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
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
    @State private var confirmCredentialDeletion = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                PulseBrand(subtitle: "CodePulse · \(model.activityLabel)")
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(model.activeCount)").font(.system(size: 28, weight: .light)).monospacedDigit()
                    Text("活跃任务").font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                }
            }.padding(.bottom, 8)
            HStack {
                PulseDetailNavigation(selection: $model.detailTab)
                Spacer()
                Label(model.ledEnabled ? "Caps LED 已启用" : "Caps LED 未启用", systemImage: "capslock")
                    .font(.system(size: 11)).foregroundStyle(PulseStyle.muted).help(model.ledStatus)
            }.padding(.vertical, 6)
            if model.ledFailed { ledDiagnostics }
            Rectangle().fill(PulseStyle.hairline).frame(height: 0.5)
            Group {
                switch model.detailTab {
                case .tasks: tasks
                case .usage: usage
                case .settings: settings
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(model.notice.isEmpty ? "CodePulse · 本地状态监视" : model.notice)
                    .font(.system(size: 11)).foregroundStyle(PulseStyle.muted).textSelection(.enabled)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.system(size: 11))
            }
        }.padding(28).frame(minWidth: 680, minHeight: 550)
            .background(PulseSurface(active: model.mode != .off))
            .foregroundStyle(PulseStyle.ink).tint(PulseStyle.accent).preferredColorScheme(.light)
            .alert("删除所选账号的本地凭据？", isPresented: $confirmCredentialDeletion) {
                Button("取消", role: .cancel) {}
                Button("删除凭据", role: .destructive) { model.deleteCredential() }
            } message: {
                Text("此操作将移除钥匙串中保存的凭据。下次查询此账号时需要重新输入令牌，不会删除供应商账号。")
            }
    }
    private var ledDiagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.ledStatus, systemImage: "exclamationmark.circle")
                .font(.system(size: 12)).foregroundStyle(PulseStyle.accent).textSelection(.enabled)
            Text("若终端自检能亮，请检查此应用的输入监控权限，授权后退出并重新打开。")
                .font(.caption).foregroundStyle(PulseStyle.muted)
            HStack {
                Button("重试 LED") { model.retryLED() }
                Button("打开输入监控设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("当前应用：\(Bundle.main.bundleURL.path)").font(.caption2).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }

    var tasks: some View {
        let timeline = model.timelineRecords
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PulseSectionHeading(title: "实时任务", detail: "\(model.shownRecords.count) 个已确认状态")
                Text(model.observerStatus).font(.system(size: 12)).foregroundStyle(PulseStyle.muted)
                    .textSelection(.enabled)
                if model.shownRecords.isEmpty {
                    PulseEmptyState(title: "静候下一次运行", message: "保持 Codex Desktop 运行。任务被确认后，将自动显示状态与观察时长。")
                    PulseActionRow(title: "检查 Codex 连接") { model.detailTab = .settings }
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(timeline.enumerated()), id: \.element.id) { index, record in
                        PulseProcessRow(record: record, observedSince: model.observedSince[record.id],
                                        isLast: index == timeline.count - 1, compact: false) {
                            model.acknowledge(record.id)
                        }
                    }
                }
                Rectangle().fill(PulseStyle.hairline).frame(height: 0.5).padding(.vertical, 8)
                PulseSectionHeading(title: "最近记录", detail: "只读历史")
                Text(model.historyStatus).font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                ForEach(model.history) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(PulseStyle.muted)
                            .frame(width: 20, height: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text(row.project).font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                                .lineLimit(1).truncationMode(.middle).help(row.project)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(row.status)
                            Text("\(row.tokens) tokens").monospacedDigit()
                        }.font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                    }.padding(.vertical, 8)
                }
            }.padding(.vertical, 14).padding(.horizontal, 4)
        }
    }
    var usage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PulseSectionHeading(title: "账户余额", detail: model.usageProviderTitle)
                if let data = model.lastUsage {
                    Text(data.account).font(.system(size: 13)).foregroundStyle(PulseStyle.muted)
                    if let balance = data.balance {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(model.money(balance, digits: 6)).font(.system(size: 56, weight: .light))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            Text(data.unit).font(.system(size: 14)).foregroundStyle(PulseStyle.muted)
                        }.textSelection(.enabled).padding(.vertical, 8)
                    }
                    if let ratio = data.ratio {
                        Text("\(data.period) · 已用 \(model.money(ratio * 100))%")
                        ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: ratio).doubleValue)))
                    }
                    if let used = data.used { Text("已用：\(model.money(used)) \(data.unit)") }
                    if let limit = data.limit { Text("总额：\(model.money(limit)) \(data.unit)") }
                    Rectangle().fill(PulseStyle.hairline).frame(height: 0.5)
                    LabeledContent("最后成功更新", value: data.fetchedAt.formatted()).font(.system(size: 12))
                    LabeledContent("数据来源", value: data.origin).font(.system(size: 12)).textSelection(.enabled)
                } else {
                    Text("—").font(.system(size: 56, weight: .light)).foregroundStyle(PulseStyle.muted)
                    PulseEmptyState(title: "连接你的账户", message: "保存账户访问令牌后，即可在菜单栏查看真实余额。")
                    Button("配置账户") { model.detailTab = .settings }.buttonStyle(.borderedProminent)
                }
                Text(model.usageStatus).font(.system(size: 12)).foregroundStyle(PulseStyle.muted).textSelection(.enabled)
                HStack(spacing: 16) {
                    Button(model.refreshing ? "正在刷新…" : "刷新余额") { model.refreshUsage() }
                        .disabled(!model.usageEnabled || model.refreshing)
                        .help("刷新遵守已配置的最小间隔与错误退避")
                    Link("Packy 官方文档", destination: URL(string: "https://docs.packyapi.ai/")!)
                }
                if model.isPackyUsage {
                    Text("在设置中选择实际登录的控制台域名，填写用户 ID 和账户访问令牌。余额以 USD 显示；账户余额不代表套餐总额，因此不生成使用百分比。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("接口依据 All API Hub 的 New API 适配；首次连接请与 PackyCode 控制台余额核对。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("按已保存的 HTTPS JSON 字段映射查询。未知或无效金额显示错误，不替换为零。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 14).padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var settings: some View {
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
                        Button("删除所选账号凭据", role: .destructive) { confirmCredentialDeletion = true }
                    }
                    TextField("刷新秒数（最少 30）", value: $model.preferences.refreshInterval, format: .number)
                    Button("保存配置与令牌并查询") { model.connectUsage() }.buttonStyle(.borderedProminent)
                }
                Button("保存设置／重试 LED") { model.save() }.buttonStyle(.borderedProminent)
                Text("关闭菜单栏后，重新打开应用即可进入此设置。数据仅保存在本机。")
                    .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).scrollContentBackground(.hidden)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
