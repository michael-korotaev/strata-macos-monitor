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

    // MARK: - Settings (stored in UserDefaults)

    @Published public var endpointText: String { didSet { persist() } }
    @Published public var pollInterval: Double { didSet { persist() } }
    @Published public var menubarFormat: MenubarFormat { didSet { persist() } }
    @Published public var detailLevel: DetailLevel { didSet { persist() } }
    @Published public var language: AppLanguage { didSet { persist() } }

    private enum Key {
        static let endpoint = "endpoint"
        static let interval = "pollInterval"
        static let format = "menubarFormat"
        static let level = "detailLevel"
        static let language = "language"
    }

    /// Starting address: Strata listens on 12388 on localhost by default.
    nonisolated public static let defaultEndpoint = "http://localhost:12388/metrics"

    public init() {
        let defaults = UserDefaults.standard
        endpointText = defaults.string(forKey: Key.endpoint) ?? Self.defaultEndpoint
        pollInterval = defaults.object(forKey: Key.interval) as? Double ?? 1.0
        menubarFormat = MenubarFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .iconAndNumber
        detailLevel = DetailLevel(rawValue: defaults.string(forKey: Key.level) ?? "") ?? .compact
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .russian
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(endpointText, forKey: Key.endpoint)
        defaults.set(pollInterval, forKey: Key.interval)
        defaults.set(menubarFormat.rawValue, forKey: Key.format)
        defaults.set(detailLevel.rawValue, forKey: Key.level)
        defaults.set(language.rawValue, forKey: Key.language)
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
        // The server reports states: idle / reading (prompt) / generating / loading.
        switch payload?.liveState {
        case "generating", "reading", "prefill": return true
        default: return false
        }
    }

    public var isLoading: Bool { payload?.liveState == "loading" }

    public var modelName: String { payload?.model ?? "—" }

    /// "NVIDIA GeForce RTX 4090" -> "RTX 4090" (the header has little room).
    public var shortGpuName: String? {
        guard let gpu = payload?.gpuName else { return nil }
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
        return nil
    }

    public var uptimeSeconds: Double? {
        guard let since = payload?.serverSince else { return nil }
        return Date().timeIntervalSince1970 - since
    }

    public var statusSymbol: String {
        switch connection {
        case .online:
            switch payload?.liveState {
            case "generating": return "bolt.horizontal.fill"
            case "loading": return "arrow.triangle.2.circlepath"
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
            case "reading", "prefill": return t("status.prompt")
            case "loading": return t("status.loading")
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
            switch payload?.liveState {
            case "generating", "reading", "prefill": return .active
            case "loading": return .busy
            default: return .idle
            }
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
            if let gpu = payload?.gpuName { parts.append(gpu) }
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

    public func fail(_ error: Error) {
        connection = .offline(Self.describe(error, language: language))
    }

    public func markConnecting() { connection = .connecting }

    /// Human readable description of a network error.
    nonisolated public static func describe(_ error: Error, language: AppLanguage) -> String {
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
