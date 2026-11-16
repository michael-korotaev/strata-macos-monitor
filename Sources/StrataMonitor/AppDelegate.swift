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

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildPopover()
        observeSettings()
        LoginItem.removeLegacyAgent()
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

    /// Клиент держит найденный адрес, поэтому опрос не перебирает варианты заново.
    private var client: MetricsClient?
    private var lastStaticFetch: Date?

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
        if client?.endpoint != url || client?.flavor != model.serverFlavor {
            client = MetricsClient(endpoint: url, flavor: model.serverFlavor)
            lastStaticFetch = nil
        }
        guard let client else { return }
        do {
            let payload = try await client.fetch()
            model.apply(payload)
            await refreshStaticIfNeeded(client)
        } catch {
            model.fail(error)
        }
        updateStatusItem()
    }

    /// Статика (имена железа, каталог моделей) меняется редко: раз в минуту.
    private func refreshStaticIfNeeded(_ client: MetricsClient) async {
        let now = Date()
        if let lastStaticFetch, now.timeIntervalSince(lastStaticFetch) < 60 { return }
        lastStaticFetch = now
        if let info = try? await client.fetchStatic() {
            model.applyStatic(info)
        }
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
        LoginItem.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try LoginItem.setEnabled(enabled)
    }
}
