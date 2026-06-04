import AppKit
import Foundation

struct AgentPingPayload: Decodable {
    let checkedAt: String?
    let summary: String
    let summaryText: String
    let decision: AgentPingDecision?
    let agents: [AgentPingAgentStatus]?
    let egress: AgentPingEgress?
    let proxyEnv: [String]
    let results: [AgentPingResult]
    let report: String?
}

struct AgentPingDecision: Decodable {
    let status: String
    let statusLabel: String
    let title: String
    let detail: String
    let action: String
}

struct AgentPingAgentStatus: Decodable {
    let name: String
    let status: String
    let statusLabel: String
    let summary: String
    let suggestion: String
}

struct AgentPingEgress: Decodable {
    let status: String
    let label: String
    let maskedIp: String?
    let networkType: String
    let source: String?
    let reason: String?
}

struct AgentPingResult: Decodable {
    let name: String
    let host: String
    let status: String
    let statusLabel: String
    let reason: String
    let suggestion: String
    let dnsMs: Double?
    let tcpMs: Double?
    let tlsMs: Double?
    let totalMs: Double?
    let resolvedIp: String?
}

struct AgentPingHistoryEntry: Codable {
    let date: Date
    let status: String
    let title: String
    let detail: String
}

@MainActor
final class AgentPingMenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let historyKey = "AgentPingRecentAnomalies"
    private var timer: Timer?
    private var lastPayload: AgentPingPayload?
    private var lastUpdated: Date?
    private static let menuWidth: CGFloat = 372

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
            button.font = Self.menuBarFont()
            button.toolTip = "Ageng网络医生 网络状态"
            button.attributedTitle = Self.statusBarTitle(status: "gray", text: "检查中")
        }
        rebuildMenu(isChecking: true)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refresh(keepMenuOpen: Bool = false) {
        statusItem.button?.attributedTitle = Self.statusBarTitle(status: "gray", text: "检查中")
        if !keepMenuOpen {
            rebuildMenu(isChecking: true)
        }

        let scriptPath = Self.agentPingScriptPath()
        DispatchQueue.global(qos: .utility).async { [weak self, scriptPath] in
            let payload = Self.runAgentPing(scriptPath: scriptPath)
            DispatchQueue.main.async {
                guard let self else { return }
                if let payload {
                    self.lastPayload = payload
                    self.lastUpdated = Date()
                    self.recordAnomalyIfNeeded(payload)
                    self.statusItem.button?.attributedTitle = self.statusTitle(for: payload)
                    self.rebuildMenu(isChecking: false)
                } else {
                    self.statusItem.button?.attributedTitle = Self.statusBarTitle(status: "red", text: "异常")
                    self.rebuildFailureMenu()
                }
            }
        }
    }

    nonisolated private static func agentPingScriptPath() -> String {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("agentping.py"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL.path
        }

        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("agentping.py")
        return scriptURL.path
    }

    nonisolated private static func runAgentPing(scriptPath: String) -> AgentPingPayload? {
        let scriptURL = URL(fileURLWithPath: scriptPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, "check", "--timeout", "3", "--json"]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(AgentPingPayload.self, from: data)
    }

    private func statusTitle(for payload: AgentPingPayload) -> NSAttributedString {
        Self.statusTitle(for: payload)
    }

    nonisolated private static func statusTitle(for payload: AgentPingPayload) -> NSAttributedString {
        let status = overallStatus(payload.results)

        let text: String
        switch status {
        case "green":
            if let maxMs = payload.results.compactMap(\.totalMs).max() {
                text = "\(Int(maxMs.rounded()))ms"
            } else {
                text = "正常"
            }
        case "yellow":
            text = "谨慎"
        default:
            if let title = payload.decision?.title {
                if title.contains("Claude") {
                    text = "Claude"
                } else if title.contains("Codex") {
                    text = "Codex"
                } else {
                    text = "异常"
                }
            } else {
                text = "异常"
            }
        }

        return statusBarTitle(status: status, text: text)
    }

    nonisolated private static func overallStatus(_ results: [AgentPingResult]) -> String {
        if results.contains(where: { $0.status == "red" }) {
            return "red"
        }
        if results.contains(where: { $0.status == "yellow" }) {
            return "yellow"
        }
        return "green"
    }

    nonisolated static func diagnoseOnce() -> String {
        guard let payload = runAgentPing(scriptPath: agentPingScriptPath()) else {
            return "● 异常"
        }
        let title = payload.decision?.title ?? payload.summary
        return "\(plainStatusText(for: payload)) - \(title)"
    }

    private func rebuildMenu(isChecking: Bool) {
        menu.removeAllItems()
        if isChecking {
            menu.addItem(summaryItem(title: "正在检查网络链路", detail: "OpenAI、Anthropic 和当前出口正在刷新。", status: "gray"))
        } else if let payload = lastPayload {
            let decision = payload.decision
            menu.addItem(summaryItem(
                title: decision?.title ?? payload.summary,
                detail: decision?.action ?? decision?.detail ?? payload.summaryText,
                status: decision?.status ?? Self.overallStatus(payload.results)
            ))
        } else {
            menu.addItem(summaryItem(title: "尚未检查", detail: "点击立即刷新后开始检测。", status: "gray"))
        }

        if let payload = lastPayload {
            if let agents = payload.agents {
                menu.addItem(Self.sectionItem("常用软件"))
                for agent in agents {
                    menu.addItem(Self.rowItem(
                        title: agent.name,
                        value: agent.summary,
                        detail: agent.suggestion,
                        status: agent.status
                    ))
                }
            }

            menu.addItem(Self.sectionItem("链路明细"))
            for result in payload.results {
                let ms = result.totalMs.map { "\(Int($0.rounded()))ms" } ?? "-"
                menu.addItem(Self.rowItem(
                    title: result.name,
                    value: ms,
                    detail: result.reason,
                    status: result.status
                ))
            }

            var environmentRows: [(String, String, String)] = []
            if let egress = payload.egress {
                let ip = egress.maskedIp.map { " · " + $0 } ?? ""
                environmentRows.append(("当前出口", egress.label + ip, egress.status))
                environmentRows.append(("网络类型", egress.networkType, "gray"))
            }
            let proxyText = payload.proxyEnv.isEmpty ? "未检测到代理环境变量" : "代理环境变量：" + payload.proxyEnv.joined(separator: ", ")
            environmentRows.append(("代理状态", proxyText, payload.proxyEnv.isEmpty ? "gray" : "green"))

            if let lastUpdated {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                environmentRows.append(("更新时间", formatter.string(from: lastUpdated), "gray"))
            }
            menu.addItem(Self.sectionItem("网络环境"))
            menu.addItem(Self.infoGroupItem(rows: environmentRows))

            let history = loadHistory()
            if !history.isEmpty {
                menu.addItem(Self.sectionItem("最近异常"))
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                for entry in history.prefix(3) {
                    menu.addItem(Self.rowItem(
                        title: formatter.string(from: entry.date),
                        value: entry.title,
                        detail: entry.detail,
                        status: entry.status
                    ))
                }
            }
        }

        menu.addItem(Self.separatorItem())
        menu.addItem(actionsItem())
        attachMenuIfNeeded()
    }

    private func rebuildFailureMenu() {
        menu.removeAllItems()
        menu.addItem(summaryItem(title: "Ageng网络医生检查失败", detail: "请确认工具文件仍在 App 资源目录中。", status: "red"))
        menu.addItem(Self.separatorItem())
        menu.addItem(actionsItem())
        attachMenuIfNeeded()
    }

    private func recordAnomalyIfNeeded(_ payload: AgentPingPayload) {
        let status = payload.decision?.status ?? Self.overallStatus(payload.results)
        guard status != "green" else { return }

        let entry = AgentPingHistoryEntry(
            date: Date(),
            status: status,
            title: payload.decision?.title ?? payload.summary,
            detail: payload.decision?.detail ?? payload.summaryText
        )

        var history = loadHistory()
        if let first = history.first,
           first.status == entry.status,
           first.title == entry.title,
           first.detail == entry.detail {
            return
        }
        history.insert(entry, at: 0)
        history = Array(history.prefix(5))

        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() -> [AgentPingHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([AgentPingHistoryEntry].self, from: data) else {
            return []
        }
        return history
    }

    private func attachMenuIfNeeded() {
        if statusItem.menu !== menu {
            statusItem.menu = menu
        }
    }

    private func summaryItem(title: String, detail: String, status: String) -> NSMenuItem {
        let height: CGFloat = 104
        let view = Self.baseView(height: height)
        let dot = Self.dotView(status: status, frame: NSRect(x: 16, y: height - 31, width: 11, height: 11))
        view.addSubview(dot)
        view.addSubview(Self.label(title, frame: NSRect(x: 35, y: height - 38, width: 260, height: 24), size: 15, weight: .semibold, color: .labelColor))

        let statusText = Self.statusLabel(status)
        view.addSubview(Self.label(statusText, frame: NSRect(x: 290, y: height - 37, width: 55, height: 22), size: 12, weight: .semibold, color: Self.statusColor(status), alignment: .right))

        view.addSubview(Self.label(detail, frame: NSRect(x: 16, y: 37, width: 330, height: 34), size: 12, weight: .regular, color: .secondaryLabelColor, lines: 2))

        let footerText: String
        if let lastUpdated {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            footerText = "更新 \(formatter.string(from: lastUpdated))"
        } else {
            footerText = "等待首次检查"
        }
        view.addSubview(Self.badgeLabel(footerText, frame: NSRect(x: 16, y: 12, width: 118, height: 22)))
        if let egress = lastPayload?.egress?.label {
            view.addSubview(Self.badgeLabel("出口 \(egress)", frame: NSRect(x: 142, y: 12, width: 156, height: 22)))
        }

        return Self.customItem(view)
    }

    nonisolated private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let mark = NSAttributedString(
            string: "P",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14.8, weight: .heavy),
                .foregroundColor: NSColor.labelColor,
                .kern: -0.6,
            ]
        )
        let markSize = mark.size()
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.18, d: 1, tx: 2.1, ty: 0))
        mark.draw(at: NSPoint(
            x: (size.width - markSize.width) / 2 - 0.1,
            y: (size.height - markSize.height) / 2 - 0.8
        ))
        context?.restoreGState()

        image.isTemplate = true
        return image
    }

    nonisolated private static func menuBarFont() -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    nonisolated private static func statusColor(_ status: String) -> NSColor {
        switch status {
        case "green":
            return .systemGreen
        case "yellow":
            return .systemYellow
        case "red":
            return .systemRed
        default:
            return .secondaryLabelColor
        }
    }

    nonisolated private static func plainStatusText(for payload: AgentPingPayload) -> String {
        let status = overallStatus(payload.results)
        switch status {
        case "green":
            if let maxMs = payload.results.compactMap(\.totalMs).max() {
                return "● \(Int(maxMs.rounded()))ms"
            }
            return "● 正常"
        case "yellow":
            return "● 谨慎"
        default:
            return "● 异常"
        }
    }

    nonisolated private static func statusBarTitle(status: String, text: String) -> NSAttributedString {
        let value = NSMutableAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: statusColor(status),
                .baselineOffset: 0,
            ]
        )
        value.append(NSAttributedString(
            string: text,
            attributes: [
                .font: menuBarFont(),
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: 0,
            ]
        ))
        return value
    }

    private static func customItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private static func baseView(height: CGFloat) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    private static func label(
        _ text: String,
        frame: NSRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        lines: Int = 1
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingTail
        label.maximumNumberOfLines = lines
        label.toolTip = text
        return label
    }

    private static func badgeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = label(text, frame: frame, size: 11.5, weight: .medium, color: .secondaryLabelColor, alignment: .center)
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        label.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        return label
    }

    private static func dotView(status: String, frame: NSRect) -> NSView {
        let dot = NSView(frame: frame)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = min(frame.width, frame.height) / 2
        dot.layer?.backgroundColor = statusColor(status).cgColor
        return dot
    }

    private static func statusLabel(_ status: String) -> String {
        switch status {
        case "green":
            return "正常"
        case "yellow":
            return "谨慎"
        case "red":
            return "异常"
        default:
            return "检查中"
        }
    }

    private static func sectionItem(_ title: String) -> NSMenuItem {
        let height: CGFloat = 28
        let view = baseView(height: height)
        view.addSubview(label(title, frame: NSRect(x: 16, y: 5, width: 220, height: 17), size: 12, weight: .semibold, color: .secondaryLabelColor))
        return customItem(view)
    }

    private static func separatorItem() -> NSMenuItem {
        let view = baseView(height: 11)
        let line = NSView(frame: NSRect(x: 16, y: 5, width: menuWidth - 32, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.58).cgColor
        view.addSubview(line)
        return customItem(view)
    }

    private static func rowItem(title: String, value: String, detail: String?, status: String) -> NSMenuItem {
        let height: CGFloat = detail?.isEmpty == false ? 50 : 38
        let view = baseView(height: height)
        view.addSubview(dotView(status: status, frame: NSRect(x: 16, y: height - 25, width: 10, height: 10)))
        view.addSubview(label(title, frame: NSRect(x: 34, y: height - 31, width: 128, height: 19), size: 13, weight: .medium, color: .labelColor))
        view.addSubview(label(value, frame: NSRect(x: 166, y: height - 31, width: 188, height: 19), size: 13, weight: .semibold, color: statusColor(status), alignment: .right))
        if let detail, !detail.isEmpty {
            view.addSubview(label(detail, frame: NSRect(x: 34, y: 8, width: 320, height: 16), size: 11.5, weight: .regular, color: .secondaryLabelColor))
        }
        return customItem(view)
    }

    private static func infoGroupItem(rows: [(String, String, String)]) -> NSMenuItem {
        let rowHeight: CGFloat = 25
        let height = CGFloat(rows.count) * rowHeight + 12
        let view = baseView(height: height)
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.34).cgColor
        for (index, row) in rows.enumerated() {
            let y = height - 10 - CGFloat(index + 1) * rowHeight
            view.addSubview(label(row.0, frame: NSRect(x: 16, y: y, width: 82, height: 18), size: 12, weight: .regular, color: .secondaryLabelColor))
            view.addSubview(label(row.1, frame: NSRect(x: 102, y: y, width: 248, height: 18), size: 12, weight: .medium, color: statusColor(row.2), alignment: .right))
        }
        return customItem(view)
    }

    private func actionsItem() -> NSMenuItem {
        let height: CGFloat = 52
        let view = Self.baseView(height: height)
        let copyButton = actionButton(title: "复制报告", frame: NSRect(x: 16, y: 11, width: 104, height: 30), action: #selector(copyReport))
        copyButton.isEnabled = lastPayload?.report != nil
        view.addSubview(copyButton)
        view.addSubview(actionButton(title: "立即刷新", frame: NSRect(x: 132, y: 11, width: 104, height: 30), action: #selector(refreshFromMenu)))
        view.addSubview(actionButton(title: "退出", frame: NSRect(x: 248, y: 11, width: 104, height: 30), action: #selector(quit)))
        return Self.customItem(view)
    }

    private func actionButton(title: String, frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        return button
    }

    @objc private func refreshFromMenu() {
        refresh(keepMenuOpen: true)
    }

    @objc private func copyReport() {
        guard let report = lastPayload?.report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--diagnose-once") {
    print(AgentPingMenuApp.diagnoseOnce())
} else {
    let app = NSApplication.shared
    let delegate = AgentPingMenuApp()
    app.delegate = delegate
    app.run()
}
