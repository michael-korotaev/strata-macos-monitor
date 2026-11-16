import Combine
import Foundation

/// Panel detail level.
public enum DetailLevel: String, CaseIterable, Identifiable {
    case compact
    case expanded

    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        Loc.string(self == .compact ? "level.compact" : "level.expanded", language: language)
    }
}

/// What to show in the menu bar.
public enum MenubarFormat: String, CaseIterable, Identifiable {
    case iconAndNumber
    case numberOnly
    case iconOnly

    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        Loc.string("menubar.format.\(rawValue)", language: language)
    }
}

public enum ConnectionState: Equatable {
    case connecting
    case online
    case offline(String)

    public var isOnline: Bool { self == .online }
}

/// Indicator state: the colour of the menu bar icon and of the badge.
public enum StatusTint {
    case active   // generating
    case busy     // loading the model or connecting
    case idle     // model loaded, nothing running
    case offline  // server unreachable
}

@MainActor
public final class MonitorModel: ObservableObject {
    // MARK: - State

    @Published public private(set) var payload: MetricsPayload?
    @Published public private(set) var connection: ConnectionState = .connecting
    @Published public private(set) var lastSuccess: Date?
    /// Static data of the modern build: hardware names and the model catalogue.
    @Published public private(set) var staticInfo: StaticInfo?

    // MARK: - Settings (stored in UserDefaults)

    @Published public var endpointText: String { didSet { persist(); staticInfo = nil } }
    /// Which Strata installation is on the other side.
    @Published public var serverFlavor: StrataFlavor { didSet { persist() } }
    @Published public var pollInterval: Double { didSet { persist() } }
    @Published public var menubarFormat: MenubarFormat { didSet { persist() } }
    @Published public var detailLevel: DetailLevel { didSet { persist() } }
    @Published public var language: AppLanguage { didSet { persist() } }
    /// Открыть панель сразу с настройками (ключ --settings при запуске).
    @Published public var showSettings = false

    private enum Key {
        static let endpoint = "endpoint"
        static let interval = "pollInterval"
        static let format = "menubarFormat"
        static let level = "detailLevel"
        static let language = "language"
        static let flavor = "serverFlavor"
    }

    /// Starting address: the host where the Strata web UI is served. The path
    /// is optional - the client looks for the monitor endpoint itself.
    nonisolated public static let defaultEndpoint = "http://localhost:12387"

    public init() {
        let defaults = UserDefaults.standard
        endpointText = defaults.string(forKey: Key.endpoint) ?? Self.defaultEndpoint
        pollInterval = defaults.object(forKey: Key.interval) as? Double ?? 1.0
        menubarFormat = MenubarFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .iconAndNumber
        detailLevel = DetailLevel(rawValue: defaults.string(forKey: Key.level) ?? "") ?? .compact
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .russian
        serverFlavor = StrataFlavor(rawValue: defaults.string(forKey: Key.flavor) ?? "") ?? .automatic
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(endpointText, forKey: Key.endpoint)
        defaults.set(pollInterval, forKey: Key.interval)
        defaults.set(menubarFormat.rawValue, forKey: Key.format)
        defaults.set(detailLevel.rawValue, forKey: Key.level)
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set(serverFlavor.rawValue, forKey: Key.flavor)
    }

    // MARK: - Localization

    /// Interface string in the current language.
    public func t(_ key: String) -> String {
        Loc.string(key, language: language)
    }

    // MARK: - Derived values

    public var endpointURL: URL? {
        let text = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.scheme != nil, url.host != nil { return url }
        return URL(string: "http://\(text)")
    }

    /// First run: the address was never changed and there is no data yet - show the setup form.
    public var needsSetup: Bool {
        payload == nil && endpointText.trimmingCharacters(in: .whitespacesAndNewlines) == Self.defaultEndpoint
    }

    /// URL of the web UI (take the root of the /metrics address).
    public var webMonitorURL: URL? {
        guard let url = endpointURL else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = "monitor"
        return components?.url
    }

    public var isGenerating: Bool {
        // The server reports phases: idle / reading (prompt) / generating /
        // loading / starting / queued. The middle ones mean the engine works.
        switch payload?.liveState {
        case "generating", "reading", "prefill", "thinking", "decision", "checkpointing":
            return true
        default:
            return false
        }
    }

    public var isLoading: Bool {
        switch payload?.liveState {
        case "loading", "starting": return true
        default: return false
        }
    }

    /// The request is waiting for the engine.
    public var isQueued: Bool {
        switch payload?.liveState {
        case "queued", "waiting": return true
        default: return false
        }
    }

    public var modelName: String {
        if let name = staticInfo?.modelName { return name }
        if let model = payload?.model { return model }
        // The engine is stopped: show the model of the last request.
        if let last = payload?.requests.first?.model { return last }
        return "—"
    }

    /// "NVIDIA GeForce RTX 4090" -> "RTX 4090" (the header has little room).
    public var shortGpuName: String? {
        guard let gpu = staticInfo?.gpuName ?? payload?.gpuName else { return nil }
        if let range = gpu.range(of: "GeForce ") {
            return String(gpu[range.upperBound...])
        }
        return gpu
    }

    /// Number for the menu bar: live tok/s while generating, rolling otherwise.
    public var headlineTPS: Double? {
        guard let payload else { return nil }
        if isGenerating, let live = payload.liveTPS, live > 0 { return live }
        // While the prompt is being read tok_s can be empty - fall back to the prefill rate.
        if payload.liveState == "reading", let prefill = payload.prefillTPSMean, prefill > 0 { return prefill }
        if let rolling = payload.hardwareTPS, rolling > 0 { return rolling }
        return nil
    }

    /// The current number is the prompt read rate, not the decode rate.
    public var headlineIsPrefill: Bool {
        guard let payload, isGenerating else { return false }
        return payload.liveState == "reading" && (payload.liveTPS ?? 0) <= 0
    }

    public var meanTPS: Double? {
        guard let payload else { return nil }
        if isGenerating, let mean = payload.liveTPSMean, mean > 0 { return mean }
        if let mean = payload.hardwareTPSMean, mean > 0 { return mean }
        // New builds have no live mean: take it from the last samples of the history.
        let recent = payload.historyTPS.compactMap { $0 }.filter { $0 > 0 }.suffix(10)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    public var uptimeSeconds: Double? {
        guard let since = payload?.serverSince else { return nil }
        return Date().timeIntervalSince(since)
    }

    public var statusSymbol: String {
        switch connection {
        case .online:
            switch payload?.liveState {
            case "generating": return "bolt.horizontal.fill"
            case "loading", "starting": return "arrow.triangle.2.circlepath"
            default: return "bolt.horizontal"
            }
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .offline:
            return "bolt.slash"
        }
    }

    public var statusLabel: String {
        switch connection {
        case .online:
            switch payload?.liveState {
            case "generating": return t("status.generating")
            case "reading", "prefill", "thinking": return t("status.prompt")
            case "loading", "starting": return t("status.loading")
            case "queued", "waiting": return t("status.queued")
            default: return t("status.idle")
            }
        case .connecting:
            return t("status.connecting")
        case .offline:
            return t("status.offline")
        }
    }

    /// Menu bar icon colour: green - the card works, red - no connection.
    public var statusTint: StatusTint {
        switch connection {
        case .online:
            if isGenerating { return .active }
            if isLoading { return .busy }
            return .idle
        case .connecting: return .busy
        case .offline: return .offline
        }
    }

    /// Tooltip text shown next to the menu bar item.
    public var tooltipText: String {
        switch connection {
        case .offline(let reason):
            return "\(t("app.name")): \(t("status.offline")) (\(reason))"
        case .connecting:
            return "\(t("app.name")): \(t("status.connecting"))…"
        case .online:
            var parts = [modelName, statusLabel]
            if let tps = headlineTPS {
                let unit = headlineIsPrefill ? t("unit.prefillTps") : t("unit.tps")
                parts.append(String(format: "%.0f %@", tps, unit))
            }
            if let gpu = staticInfo?.gpuName ?? payload?.gpuName { parts.append(gpu) }
            if let util = payload?.gpuUtil { parts.append(String(format: "GPU %.0f%%", util)) }
            return parts.joined(separator: " · ")
        }
    }

    /// Snapshot of the readings as text, for the clipboard.
    public func snapshotText() -> String {
        guard let payload else { return "\(t("app.name")): \(t("status.offline"))" }
        return """
        Strata \(payload.model ?? "?") — \(statusLabel)
        tok/s: \(headlineTPS.map { String(format: "%.1f", $0) } ?? "—")
        GPU: \(payload.gpuUtil.map { String(format: "%.0f%%", $0) } ?? "—") \
        VRAM: \(Format.gib(payload.gpuMemUsed))/\(Format.gib(payload.gpuMemTotal)) GiB \
        temp: \(payload.gpuTemp.map { String(format: "%.0f°C", $0) } ?? "—") \
        power: \(payload.gpuPower.map { String(format: "%.0fW", $0) } ?? "—")
        requests: \(payload.totalRequests ?? 0)
        """
    }

    // MARK: - Applying a response

    public func apply(_ payload: MetricsPayload) {
        self.payload = payload
        connection = .online
        lastSuccess = Date()
    }

    /// Static data of the modern build (hardware names, model catalogue).
    public func applyStatic(_ info: StaticInfo?) {
        staticInfo = info
    }

    public func fail(_ error: Error) {
        connection = .offline(Self.describe(error, language: language))
    }

    public func markConnecting() { connection = .connecting }

    /// Human readable description of a network error.
    nonisolated public static func describe(_ error: Error, language: AppLanguage) -> String {
        if let clientError = error as? MetricsClient.ClientError {
            return clientError.message(language: language)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut: return Loc.string("error.timeout", language: language)
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost: return Loc.string("error.unreachable", language: language)
            case NSURLErrorNetworkConnectionLost: return Loc.string("error.lost", language: language)
            default: break
            }
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
