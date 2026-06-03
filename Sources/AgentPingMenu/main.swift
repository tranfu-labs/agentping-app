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

    private func refresh() {
        statusItem.button?.attributedTitle = Self.statusBarTitle(status: "gray", text: "检查中")
        rebuildMenu(isChecking: true)

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
            menu.addItem(Self.infoItem("正在检查网络链路..."))
        } else if let payload = lastPayload {
            let decision = payload.decision
            menu.addItem(Self.statusItem(
                title: decision?.title ?? payload.summary,
                detail: decision?.detail,
                status: decision?.status ?? Self.overallStatus(payload.results),
                isStrong: true
            ))
            if let action = decision?.action {
                menu.addItem(Self.infoItem("下一步：" + action))
            }
        } else {
            menu.addItem(Self.infoItem("尚未检查"))
        }

        if let payload = lastPayload {
            menu.addItem(.separator())

            if let agents = payload.agents {
                menu.addItem(Self.sectionItem("常用软件"))
                for agent in agents {
                    menu.addItem(Self.statusItem(
                        title: "\(agent.name)：\(agent.summary)",
                        detail: agent.suggestion,
                        status: agent.status
                    ))
                }
                menu.addItem(.separator())
            }

            menu.addItem(Self.sectionItem("链路明细"))
            for result in payload.results {
                let ms = result.totalMs.map { "\(Int($0.rounded()))ms" } ?? "-"
                menu.addItem(Self.statusItem(
                    title: "\(result.name)：\(ms)",
                    detail: "\(result.reason)\n\(result.suggestion)",
                    status: result.status
                ))
            }

            menu.addItem(.separator())
            if let egress = payload.egress {
                let ip = egress.maskedIp.map { " · " + $0 } ?? ""
                let egressItem = Self.statusItem(
                    title: "当前出口：" + egress.label + ip,
                    detail: egress.reason,
                    status: egress.status
                )
                menu.addItem(egressItem)
                menu.addItem(Self.infoItem("网络类型：" + egress.networkType))
            }

            let proxyText = payload.proxyEnv.isEmpty ? "未检测到代理环境变量" : "代理环境变量：" + payload.proxyEnv.joined(separator: ", ")
            menu.addItem(Self.infoItem(proxyText))

            if let lastUpdated {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                menu.addItem(Self.infoItem("更新时间：" + formatter.string(from: lastUpdated)))
            }

            menu.addItem(.separator())
            menu.addItem(Self.sectionItem("最近异常"))
            let history = loadHistory()
            if history.isEmpty {
                menu.addItem(Self.infoItem("暂无异常记录"))
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                for entry in history.prefix(5) {
                    menu.addItem(Self.statusItem(
                        title: "\(formatter.string(from: entry.date)) \(entry.title)",
                        detail: entry.detail,
                        status: entry.status
                    ))
                }
            }
        }

        menu.addItem(.separator())
        let copyItem = NSMenuItem(title: "复制诊断报告", action: #selector(copyReport), keyEquivalent: "c")
        copyItem.target = self
        copyItem.isEnabled = lastPayload?.report != nil
        menu.addItem(copyItem)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "退出 Ageng网络医生", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func rebuildFailureMenu() {
        menu.removeAllItems()
        menu.addItem(Self.statusItem(title: "Ageng网络医生 检查失败", detail: nil, status: "red", isStrong: true))
        menu.addItem(Self.infoItem("请确认工具文件仍在 App 资源目录中。"))
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "退出 Ageng网络医生", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
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

    nonisolated private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.labelColor.setFill()
        let mark = NSAttributedString(
            string: "P",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.4, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .kern: -0.3,
            ]
        )
        let markSize = mark.size()
        mark.draw(at: NSPoint(
            x: (size.width - markSize.width) / 2,
            y: (size.height - markSize.height) / 2 - 0.4
        ))

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

    nonisolated private static func sectionItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    nonisolated private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        item.toolTip = title
        return item
    }

    nonisolated private static func statusItem(title: String, detail: String?, status: String, isStrong: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let value = NSMutableAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: isStrong ? 14 : 13, weight: .semibold),
                .foregroundColor: statusColor(status),
            ]
        )
        value.append(NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: isStrong ? 14 : 13, weight: isStrong ? .semibold : .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        item.attributedTitle = value
        item.toolTip = detail
        return item
    }

    @objc private func refreshFromMenu() {
        refresh()
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
