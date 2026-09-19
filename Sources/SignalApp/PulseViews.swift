import AppKit
import SwiftUI
import SignalCore

enum PulseStyle {
    static let cyan = Color(red: 125 / 255, green: 235 / 255, blue: 1)
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.17)
    static let muted = Color(red: 0.29, green: 0.33, blue: 0.38)
    static let silver = Color(red: 0.94, green: 0.955, blue: 0.97)
    static let accent = Color(red: 0, green: 0.36, blue: 0.44)
    static let hairline = ink.opacity(0.12)
}

struct PulseBrand: View {
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(PulseStyle.accent)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.8), lineWidth: 0.5)
                }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pulse").font(.system(size: 24, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                    .lineLimit(1)
            }
        }
    }
}

struct PulseSectionHeading: View {
    var title: String
    var detail: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(detail).font(.system(size: 11, design: .monospaced)).monospacedDigit()
                .foregroundStyle(PulseStyle.muted)
        }
    }
}

struct PulseActionRow: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }.foregroundStyle(PulseStyle.muted)
                .frame(minHeight: 28).contentShape(Rectangle())
        }.buttonStyle(.borderless)
    }
}

struct PulseEmptyState: View {
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path").font(.system(size: 18, weight: .light))
                .foregroundStyle(PulseStyle.muted).frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(message).font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}

extension Model {
    var timelineRecords: [TaskRecord] {
        shownRecords.sorted {
            let left = $0.mode == .blink ? 0 : ($0.isRunning ? 1 : 2)
            let right = $1.mode == .blink ? 0 : ($1.isRunning ? 1 : 2)
            return left == right ? $0.updatedAt > $1.updatedAt : left < right
        }
    }
}

struct GlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PulseSurface: View {
    var active: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topTrailing) {
            material
            if !reduceTransparency {
                Ellipse().fill(PulseStyle.cyan)
                    .frame(width: 180, height: 95).blur(radius: 42)
                    .offset(x: 40, y: -35)
                    .opacity(active ? 0.09 : 0.015)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: active)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(contrast == .increased ? PulseStyle.ink.opacity(0.55) : .white.opacity(0.75), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var material: some View {
        if reduceTransparency || contrast == .increased {
            PulseStyle.silver
        } else if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(PulseStyle.silver.opacity(0.45)),
                                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            ZStack {
                GlassMaterial()
                PulseStyle.silver.opacity(0.55)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.75), lineWidth: 1)
            }
        }
    }
}

struct PulseIconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        styledButton.accessibilityLabel(label).help(label)
    }

    @ViewBuilder private var styledButton: some View {
        if #available(macOS 26, *), !reduceTransparency {
            button.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
        } else {
            button.buttonStyle(PulseControlStyle())
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 30).contentShape(Circle())
        }
    }
}

struct PulseControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? PulseStyle.ink : PulseStyle.muted)
            .background(configuration.isPressed ? PulseStyle.ink.opacity(0.08) : .white.opacity(hovering ? 0.7 : 0.4), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(hovering ? 0.9 : 0.6), lineWidth: 0.5) }
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

struct PulseDetailNavigation: View {
    @Binding var selection: DetailTab

    var body: some View {
        Picker("详情导航", selection: $selection) {
            Text("任务").tag(DetailTab.tasks)
            Text("用量").tag(DetailTab.usage)
            Text("设置").tag(DetailTab.settings)
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.large)
        .frame(width: 320)
    }
}

struct PulseIndicator: View {
    var mode: LEDMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !visible || reduceMotion || mode != .solid)) { context in
            let wave = (sin(context.date.timeIntervalSinceReferenceDate * 2) + 1) / 2
            let strength = mode == .off ? 0.3 : (reduceMotion ? 1 : 0.55 + wave * 0.45)
            ZStack {
                Circle().fill(PulseStyle.cyan)
                    .frame(width: 20, height: 20).blur(radius: 4)
                    .opacity(mode == .off ? 0 : mode == .blink ? 0.12 : strength * 0.2)
                if mode == .blink {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(PulseStyle.accent)
                } else {
                    Circle().fill(mode == .off ? PulseStyle.ink.opacity(0.5) : PulseStyle.accent)
                        .frame(width: 6, height: 6).opacity(strength)
                }
            }.frame(width: 20, height: 20)
        }.accessibilityHidden(true)
            .onAppear { visible = true }.onDisappear { visible = false }
    }
}

struct PulsePopover: View {
    @ObservedObject var model: Model
    var maximumHeight: CGFloat = 700
    var openDetails: (DetailTab) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var orderedRecords: [TaskRecord] { model.timelineRecords }

    var body: some View {
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView { panelContent }
        }
        .frame(width: 352).frame(maxHeight: maximumHeight)
        .background(PulseSurface(active: model.mode != .off))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(PulseStyle.ink).tint(PulseStyle.accent).preferredColorScheme(.light)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 28)
            processes
            separator.padding(.vertical, 18)
            balance
            separator.padding(.vertical, 18)
            capsSignal
            separator.padding(.top, 20).padding(.bottom, 14)
            footer
        }
        .padding(24).frame(width: 352)
    }

    private var separator: some View { Rectangle().fill(PulseStyle.hairline).frame(height: 0.5) }

    private var header: some View {
        HStack(spacing: 10) {
            PulseBrand(subtitle: "Codex · \(model.activityLabel)")
            Spacer()
            PulseIconButton(symbol: "gearshape", label: "打开设置") { openDetails(.settings) }
        }
    }

    private var processes: some View {
        VStack(alignment: .leading, spacing: 14) {
            PulseSectionHeading(title: "Processes", detail: "\(model.activeCount) 活跃")
            if orderedRecords.isEmpty {
                PulseEmptyState(title: "静候下一次运行", message: "连接 Codex 后，任务状态会自动出现在这里。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(orderedRecords.prefix(12).enumerated()), id: \.element.id) { index, record in
                            PulseProcessRow(record: record, observedSince: model.observedSince[record.id],
                                            isLast: index == min(orderedRecords.count, 12) - 1) {
                                model.acknowledge(record.id)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(orderedRecords.count, 2)) * 66)
            }
            PulseActionRow(title: orderedRecords.isEmpty ? "检查 Codex 连接" : "查看全部任务") {
                openDetails(orderedRecords.isEmpty ? .settings : .tasks)
            }
        }
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Balance").font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                PulseIconButton(symbol: "arrow.clockwise", label: !model.usageEnabled ? "余额查询未启用，请先连接账户" : model.refreshing ? "余额刷新中" : "刷新余额") {
                    model.refreshUsage()
                }.disabled(!model.usageEnabled || model.refreshing)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                balanceNumber
                    .font(.system(size: 44, weight: .light)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let usage = model.lastUsage {
                    Text(usage.unit).font(.system(size: 11, weight: .medium)).foregroundStyle(PulseStyle.muted)
                }
                Spacer(minLength: 0)
            }.textSelection(.enabled)
            if let usage = model.lastUsage {
                Text(usage.account).font(.system(size: 11)).foregroundStyle(PulseStyle.muted).lineLimit(1)
                if let ratio = usage.ratio {
                    let progress = min(1, max(0, NSDecimalNumber(decimal: ratio).doubleValue))
                    Capsule().fill(PulseStyle.ink.opacity(0.08))
                        .overlay {
                            Capsule().fill(PulseStyle.accent.opacity(0.85))
                                .scaleEffect(x: progress, y: 1, anchor: .leading)
                        }
                        .overlay { Capsule().strokeBorder(PulseStyle.hairline, lineWidth: 0.5) }
                        .frame(height: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: progress)
                        .accessibilityLabel("用量").accessibilityValue("已用 \(model.money(ratio * 100))%")
                    HStack {
                        Text("已用 \(model.money(ratio * 100))%")
                        Spacer()
                        Text(usage.period).lineLimit(1)
                    }.font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                    Text("数据源未提供重置时间").font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                } else {
                    Text("按余额计费 · 无套餐进度或重置时间")
                        .font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                }
                if !model.usageStatus.hasPrefix("已更新") {
                    Label(model.refreshing ? "正在刷新" : "上次数据 · 刷新未完成", systemImage: "clock")
                        .font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                    if !model.refreshing {
                        Text(model.usageStatus).font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                            .lineLimit(2).help(model.usageStatus)
                    }
                }
                PulseActionRow(title: "查看账单详情") { openDetails(.usage) }
                    .help(model.usageStatus)
            } else {
                Text(model.usageStatus).font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                    .lineLimit(2).help(model.usageStatus)
                PulseActionRow(title: "连接账户") { openDetails(.settings) }
            }
        }
    }

    @ViewBuilder private var balanceNumber: some View {
        let value = model.lastUsage?.balance.map { model.money($0, digits: 6) } ?? "—"
        if #available(macOS 14, *) {
            Text(value).contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: value)
        } else { Text(value) }
    }

    private var capsSignal: some View {
        VStack(alignment: .leading, spacing: 13) {
            PulseSectionHeading(title: "Caps Signal", detail: !model.ledEnabled ? "未启用" : model.ledFailed ? "不可用" : "已启用")
            HStack(spacing: 14) {
                Image(systemName: "capslock").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PulseStyle.muted).frame(width: 24, height: 24).accessibilityHidden(true)
                CapsDots(mode: model.ledEnabled && !model.ledFailed ? model.mode : .off,
                         interval: model.ledBlinkInterval)
                Spacer()
                Text(!model.ledEnabled ? "未启用" : model.ledFailed ? "写入失败" : model.mode == .blink ? "快闪" : model.mode == .solid ? "常亮" : "熄灭")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(PulseStyle.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(PulseStyle.hairline, lineWidth: 0.5)
            }
            Text(model.ledFailed ? model.ledStatus : "Caps Lock LED · 仅控制指示灯")
                .font(.system(size: 10)).foregroundStyle(PulseStyle.muted).lineLimit(2)
                .help(model.ledStatus)
            if model.ledFailed {
                Button("重试 LED") { model.retryLED() }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(PulseStyle.accent)
            }
        }.accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 10))
                    .foregroundStyle(PulseStyle.muted)
                Text(model.observerStatus).font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                    .lineLimit(2).help(model.observerStatus)
            }
            HStack {
                let updated = ([model.lastUsage?.fetchedAt] + model.shownRecords.map { Optional($0.updatedAt) }).compactMap { $0 }.max()
                if let updated {
                    Text("更新于 \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(PulseStyle.muted)
                } else {
                    Text("尚无实时更新").font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .font(.system(size: 10)).foregroundStyle(PulseStyle.muted).buttonStyle(.plain)
            }
        }
    }
}

struct PulseProcessRow: View {
    var record: TaskRecord
    var observedSince: Date?
    var isLast: Bool
    var compact = true
    var acknowledge: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var visible = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 3) {
                PulseIndicator(mode: record.mode)
                Rectangle().fill(PulseStyle.hairline.opacity(isLast ? 0 : 1)).frame(width: 1)
            }.frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(record.title).font(.system(size: 12, weight: .medium)).lineLimit(1).help(record.title)
                    Spacer(minLength: 0)
                    if let observedSince {
                        TimelineView(.animation(minimumInterval: 1, paused: !visible)) { context in
                            Text(elapsed(since: observedSince, now: context.date))
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(PulseStyle.muted)
                                .accessibilityLabel("已观察时长")
                                .accessibilityValue(elapsed(since: observedSince, now: context.date))
                        }.help("本次连续观察时长，不代表任务的实际总耗时")
                    }
                }
                HStack(spacing: 5) {
                    Text(record.phase.label)
                        .foregroundStyle(record.mode == .blink ? PulseStyle.accent : PulseStyle.muted)
                    Text("·")
                    Text(URL(fileURLWithPath: record.project).lastPathComponent).lineLimit(1).help(record.project)
                    Spacer(minLength: 0)
                    if record.phase == .interrupted && !record.acknowledged {
                        Button("已知晓", action: acknowledge).buttonStyle(.plain).foregroundStyle(PulseStyle.accent)
                    }
                }.font(.system(size: 11)).foregroundStyle(PulseStyle.muted)
                if !compact {
                    HStack {
                        Text(record.source + (record.acknowledged ? " · 已知晓" : ""))
                        Spacer()
                        Text(record.updatedAt, style: .time).monospacedDigit()
                    }.font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
                }
            }.padding(.top, 2)
        }
        .frame(height: compact ? 66 : 84, alignment: .top)
        .opacity(record.mode == .off && contrast != .increased ? 0.82 : 1)
        .accessibilityElement(children: .contain)
        .onAppear { visible = true }.onDisappear { visible = false }
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct CapsDots: View {
    var mode: LEDMode
    var interval: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: max(0.05, interval / 2), paused: !visible || reduceMotion || mode != .blink)) { context in
            let lit = mode == .solid || (mode == .blink && (reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / max(0.1, interval)) % 2 == 0))
            HStack(spacing: 8) {
                ForEach(0..<8) { _ in
                    Circle().fill(lit ? PulseStyle.cyan : PulseStyle.ink.opacity(0.13))
                        .frame(width: 7, height: 7)
                        .overlay { Circle().strokeBorder(PulseStyle.accent.opacity(lit ? 0.65 : 0.12), lineWidth: 0.5) }
                        .shadow(color: PulseStyle.cyan.opacity(lit ? 0.25 : 0), radius: 4)
                }
            }.frame(height: 16)
        }.accessibilityHidden(true)
            .onAppear { visible = true }.onDisappear { visible = false }
    }
}
