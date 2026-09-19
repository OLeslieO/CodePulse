import Foundation
import AppKit
import SignalCore
import SignalMac

enum DetailTab: Hashable { case tasks, usage, settings }

@MainActor final class Model: ObservableObject {
    @Published var detailTab: DetailTab = .tasks
    @Published private(set) var observedSince: [String: Date] = [:]
    @Published var preferences = Preferences.load()
    @Published var records: [TaskRecord] = []
    @Published var history: [HistoryEntry] = []
    @Published var mode: LEDMode = .off
    @Published var ledStatus = "LED 未启用"
    @Published private(set) var ledFailed = false
    @Published var observerStatus = "实时观察未连接"
    @Published var historyStatus = ""
    @Published var usageStatus = "在设置中选择 PackyCode 账号并保存账户访问令牌后，可查询余额"
    @Published var lastUsage: UsageSnapshot?
    @Published var refreshing = false
    @Published var notice = ""
    @Published var credential = ""
    private var active = Preferences.load()
    var changed: (() -> Void)?
    private var engine = StateEngine()
    private let driver = LEDDriver()
    private let observer = AppServerObserver()
    private let desktopObserver = DesktopObserver()
    private var observing = true
    private var ticker: Timer?
    private var health: [String: Date] = [:]
    private var nextHistory = Date.distantPast
    private var historyBusy = false
    private var nextUsage = Date.distantPast
    private var usageGeneration = UUID()
    private var usageJob: Task<Void, Never>?
    private var usageFailures = 0
    private var authPaused = false
    private var lastLED: Bool?
    private var lastLEDWrite = Date.distantPast
    private var sleeping = false

    var showMenu: Bool { active.showMenu }
    var ledEnabled: Bool { active.ledEnabled }
    var ledBlinkInterval: TimeInterval { active.blinkInterval }
    var isPackyUsage: Bool { active.selectedUsageProvider == .packyCode }
    var usageProviderTitle: String { active.selectedUsageProvider.label }
    var usageEnabled: Bool { active.usageEnabled }
    var activeCount: Int { shownRecords.filter { $0.isRunning || $0.mode == .blink }.count }
    var activityLabel: String {
        mode == .blink ? "需要处理" : (mode == .solid ? "正在运行" : "待机")
    }
    private var usesDesktop: Bool { active.codexSocket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var shownRecords: [TaskRecord] {
        let filter = active.projectFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { filter.isEmpty || $0.project.localizedCaseInsensitiveContains(filter) }
    }
    var menuTitle: String {
        let symbol = mode == .blink ? "!" : (mode == .solid ? "●" : "○")
        let active = shownRecords.filter { $0.isRunning || $0.mode == .blink }.count
        if let usage = lastUsage, let balance = usage.balance {
            return "\(symbol) \(active) · \(money(balance, digits: 6)) \(usage.unit)\(usageStatus.hasPrefix("已更新") ? "" : " ⚠")"
        }
        if let ratio = lastUsage?.ratio {
            return "\(symbol) \(active) · \(money(ratio * 100))%\(usageStatus.hasPrefix("已更新") ? "" : " ⚠")"
        }
        return "\(symbol) Codex \(active)"
    }
    func money(_ value: Decimal, digits: Int = 2) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    func start() {
        observer.onEvent = { [weak self] event in
            guard let self, !self.usesDesktop else { return }; self.receive(event)
        }
        observer.onStatus = { [weak self] status in
            guard let self, !self.usesDesktop else { return }; self.observerStatus = status
        }
        desktopObserver.onEvent = { [weak self] event in
            guard let self, self.usesDesktop else { return }; self.receive(event)
        }
        desktopObserver.onStatus = { [weak self] status in
            guard let self, self.usesDesktop else { return }; self.observerStatus = status
        }
        connect()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        }
        tick()
    }
    @discardableResult func save() -> Bool {
        guard preferences.blinkInterval.isFinite, preferences.refreshInterval.isFinite else {
            notice = "时间间隔必须是有限数值"; return false
        }
        preferences.blinkInterval = max(0.1, min(1, preferences.blinkInterval))
        preferences.refreshInterval = max(30, preferences.refreshInterval)
        do {
            if preferences.usageEnabled { _ = try preferences.usageCredentialAccount() }
            try preferences.save(); notice = "设置已保存"
        } catch { notice = error.localizedDescription; return false }
        let usageChanged = active.usage != preferences.usage || active.usageEnabled != preferences.usageEnabled ||
            active.selectedUsageProvider != preferences.selectedUsageProvider || active.packySettings != preferences.packySettings
        let observerChanged = active.codexHome != preferences.codexHome || active.codexBinary != preferences.codexBinary || active.codexSocket != preferences.codexSocket
        active = preferences
        if observerChanged { connect() }
        if usageChanged {
            resetUsage()
        }
        ledFailed = false
        if !active.ledEnabled { driver.release(); lastLED = nil; ledStatus = driver.status }
        if !active.historyEnabled { history = []; historyStatus = "历史读取已关闭" }
        recalculate()
        return true
    }
    private func resetUsage() {
        usageGeneration = UUID(); usageJob?.cancel(); usageJob = nil; refreshing = false
        lastUsage = nil; nextUsage = .distantPast; authPaused = false; usageFailures = 0
        usageStatus = active.usageEnabled ? "等待刷新…" : "用量查询已关闭"
        changed?()
    }
    @discardableResult func saveCredential() -> Bool {
        do {
            let account = try preferences.usageCredentialAccount()
            guard !credential.isEmpty else { notice = "未输入新凭据；现有凭据保持不变"; return false }
            let token = try PackyAccount.normalizedToken(credential)
            try Credentials.set(token, account: account)
            credential = ""; notice = "凭据已保存到钥匙串"
            if (try? active.usageCredentialAccount()) == account { resetUsage() }
            return true
        } catch { notice = error.localizedDescription; return false }
    }
    func deleteCredential() {
        do {
            let account = try preferences.usageCredentialAccount()
            try Credentials.set("", account: account); notice = "所选账号的凭据已删除"
            if (try? active.usageCredentialAccount()) == account {
                resetUsage(); authPaused = true; usageStatus = "凭据已删除，请保存新凭据后查询"
            }
        }
        catch { notice = error.localizedDescription }
    }
    func connectUsage() {
        preferences.usageEnabled = true
        guard save() else { return }
        if !credential.isEmpty, !saveCredential() { return }
        refreshUsage()
    }
    func connect() {
        observing = true
        engine.remove(source: observer.source)
        engine.remove(source: desktopObserver.source)
        recalculate()
        if usesDesktop {
            observer.stop()
            desktopObserver.start(home: active.codexHome)
        } else {
            desktopObserver.stop()
            observer.start(binary: active.codexBinary, socket: active.codexSocket)
        }
    }
    func disconnect() { observing = false; observer.stop(); desktopObserver.stop() }
    func retryLED() {
        guard active.ledEnabled else { return }
        driver.release()
        lastLED = nil; lastLEDWrite = .distantPast; ledFailed = false
        ledStatus = "正在重新连接 LED…"
        tick()
    }
    func acknowledge(_ id: String) { engine.acknowledge(id); recalculate() }
    func receive(_ event: TaskEvent) {
        if event.kind == .heartbeat { health[event.source] = Date() }
        if event.kind == .disconnected { health.removeValue(forKey: event.source) }
        engine.apply(event); recalculate()
    }
    private func recalculate() {
        let latest = engine.records.values.sorted { $0.updatedAt > $1.updatedAt }
        let previous = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var starts = observedSince
        for record in latest {
            if record.isRunning || record.mode == .blink {
                if starts[record.id] == nil || previous[record.id]?.turn != record.turn {
                    starts[record.id] = Date()
                }
            } else { starts.removeValue(forKey: record.id) }
        }
        let ids = Set(latest.map(\.id))
        starts = starts.filter { ids.contains($0.key) }
        if starts != observedSince { observedSince = starts }
        records = latest
        mode = engine.mode(for: shownRecords)
        changed?()
    }
    private func tick() {
        guard !sleeping else { return }
        do { for event in try EventInbox.drain() { receive(event) } }
        catch { notice = "事件队列读取失败：\(error.localizedDescription)" }
        for source in Array(health.keys) where Date().timeIntervalSince(health[source]!) > 15 {
            health.removeValue(forKey: source); engine.disconnect(source: source); recalculate()
        }
        if active.ledEnabled && !ledFailed {
            let value = mode == .solid || (mode == .blink && Int(Date().timeIntervalSinceReferenceDate / active.blinkInterval) % 2 == 0)
            if lastLED != value || Date().timeIntervalSince(lastLEDWrite) >= 1 {
                do {
                    try driver.set(value, force: true); lastLED = value; lastLEDWrite = Date(); ledStatus = driver.status
                } catch {
                    let detail = error.localizedDescription; driver.release(); ledStatus = detail; ledFailed = true
                }
            }
        }
        if active.historyEnabled && !historyBusy && Date() >= nextHistory {
            historyBusy = true; nextHistory = Date().addingTimeInterval(10)
            let home = active.codexHome
            Task {
                let result = await Task.detached { Result { try HistoryReader.read(home: home) } }.value
                historyBusy = false
                switch result {
                case .success(let entries):
                    guard active.historyEnabled, active.codexHome == home else { return }
                    history = entries; historyStatus = "只读历史模式：不驱动 LED，不推断审批"
                case .failure(let error): historyStatus = error.localizedDescription
                }
            }
        }
        if active.usageEnabled && !refreshing && !authPaused && Date() >= nextUsage { refreshUsage() }
    }
    func refreshUsage() {
        guard active.usageEnabled, !refreshing, !authPaused, Date() >= nextUsage else { return }
        let mapping = active.usage, generation = usageGeneration
        let provider = active.selectedUsageProvider, packy = active.packySettings
        refreshing = true; usageStatus = "正在刷新…"
        usageJob = Task {
            do {
                let value: UsageSnapshot
                switch provider {
                case .packyCode: value = try await UsageClient.fetchPacky(account: packy)
                case .customJSON: value = try await UsageClient.fetch(mapping: mapping)
                }
                guard generation == usageGeneration else { return }
                lastUsage = value
                usageStatus = provider == .packyCode ? "已更新 · PackyCode 账户余额" : "已更新（按配置字段读取）"
                usageFailures = 0
                nextUsage = Date().addingTimeInterval(max(30, active.refreshInterval))
            } catch {
                guard generation == usageGeneration else { return }
                usageFailures = min(usageFailures + 1, 6)
                var delay = min(1800, 30 * pow(2, Double(usageFailures)))
                if let http = error as? UsageHTTPError {
                    if [401, 403].contains(http.status) { authPaused = true }
                    if let retry = http.retryAfter { delay = max(delay, retry) }
                }
                if error is PackyAccountError { authPaused = true }
                usageStatus = error.localizedDescription + (lastUsage == nil ? "" : " · 上次数据已过期")
                nextUsage = Date().addingTimeInterval(delay + Double.random(in: 0...3))
            }
            refreshing = false; changed?()
        }
    }
    private func sleep() {
        sleeping = true; observer.stop(); desktopObserver.stop(); driver.release(); lastLED = nil
        for source in health.keys { engine.disconnect(source: source) }; health.removeAll(); recalculate()
    }
    private func wake() {
        sleeping = false; ledFailed = false; nextHistory = .distantPast
        if observing { connect() }
        tick()
    }
    func shutdown() { ticker?.invalidate(); usageJob?.cancel(); observer.stop(); desktopObserver.stop(); driver.release() }
}
