import AppKit
import Combine
import ServiceManagement
import SwiftUI
import StrataMonitorKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Access from the SwiftUI views (open browser, quit, launch at login).
    nonisolated(unsafe) static var shared: AppDelegate!

    private let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var pollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private enum Launch {
        static let label = "io.github.michael-korotaev.strata-monitor"
        static let plistName = "io.github.michael-korotaev.strata-monitor.plist"
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildPopover()
        observeSettings()
        refreshLaunchAgentIfNeeded()
        model.markConnecting()
        updateStatusItem()
        startPolling()

        // Запуск с --settings сразу открывает панель с настройками.
        if CommandLine.arguments.contains("--settings") {
            model.showSettings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func buildPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let controller = NSHostingController(rootView: MenuBarPanelView().environmentObject(model))
        popover.contentViewController = controller
        applyPopoverSize()
    }

    private func applyPopoverSize() {
        let width: CGFloat = 340
        let height: CGFloat = model.detailLevel == .compact ? 420 : 700
        popover.contentSize = NSSize(width: width, height: height)
    }

    private func observeSettings() {
        model.$detailLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyPopoverSize()
            }
            .store(in: &cancellables)
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        openPanel()
    }

    private func openPanel() {
        NSApp.activate(ignoringOtherApps: true)
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                let interval = max(self.model.pollInterval, 0.25)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func pollOnce() async {
        guard let url = model.endpointURL else {
            model.fail(MetricsClient.ClientError.badURL(model.endpointText))
            updateStatusItem()
            return
        }
        do {
            let payload = try await MetricsClient(endpoint: url).fetch()
            model.apply(payload)
        } catch {
            model.fail(error)
        }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = StatusImageRenderer.render(
            tint: model.statusTint,
            symbol: model.statusSymbol,
            tps: model.headlineTPS,
            format: model.menubarFormat
        )
        button.image = image
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        model.tooltipText
    }

    // MARK: - Panel actions

    func openWebMonitor() {
        guard let url = model.webMonitorURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copySnapshot() {
        let text = model.snapshotText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    var launchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(Launch.plistName)
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        let directory = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if enabled {
            let executable = Bundle.main.bundlePath + "/Contents/MacOS/StrataMonitor"
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(Launch.label)</string>
                <key>ProgramArguments</key>
                <array><string>\(executable)</string></array>
                <key>RunAtLoad</key><true/>
                <key>KeepAlive</key><false/>
                <key>ProcessType</key><string>Interactive</string>
            </dict>
            </plist>
            """
            try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            try? runLaunchctl(["unload", launchAgentURL.path])
            try? runLaunchctl(["load", launchAgentURL.path])
        } else {
            try? runLaunchctl(["unload", launchAgentURL.path])
            try? FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    /// If the app moved - rewrite the path inside the launch agent.
    private func refreshLaunchAgentIfNeeded() {
        guard launchAtLoginEnabled,
              let text = try? String(contentsOf: launchAgentURL, encoding: .utf8),
              !text.contains(Bundle.main.bundlePath)
        else { return }
        try? setLaunchAtLogin(true)
    }

    private func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "StrataMonitor", code: Int(process.terminationStatus))
        }
    }
}
