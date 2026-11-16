import Foundation

/// HTTP client for Strata.
///
/// The server moves its endpoints between builds, so the client does not
/// insist on one exact URL: it remembers the address that worked and, when it
/// stops working, looks for the monitor endpoint again - the same host on the
/// known ports, the known paths on each of them.
public final class MetricsClient {
    public enum ClientError: LocalizedError {
        case badURL(String)
        case badStatus(Int)
        case emptyBody
        /// The server answered, but none of the known endpoints had monitor data.
        case noMonitorEndpoint

        /// Text for the interface (the language is chosen by the caller).
        public func message(language: AppLanguage) -> String {
            switch self {
            case .badURL(let text):
                return "\(Loc.string("error.badURL", language: language)) \(text)"
            case .badStatus(let code):
                return String(format: Loc.string("error.badStatus", language: language), code)
            case .emptyBody:
                return Loc.string("error.emptyBody", language: language)
            case .noMonitorEndpoint:
                return Loc.string("error.noMonitor", language: language)
            }
        }

        public var errorDescription: String? {
            switch self {
            case .badURL(let text): return "Некорректный адрес: \(text)"
            case .badStatus(let code): return "Сервер ответил HTTP \(code)"
            case .emptyBody: return "Пустой ответ сервера"
            case .noMonitorEndpoint: return "Не нашёл данные монитора на сервере"
            }
        }
    }

    /// Paths where the monitor data lives, in the order they are tried.
    public static let knownPaths = ["/api/monitor", "/metrics"]

    /// Ports where Strata serves its web API, tried when the given one fails.
    public static let knownPorts = [12387, 12388]

    public let endpoint: URL

    /// Which Strata installation is expected on the other side.
    public let flavor: StrataFlavor

    /// Address that answered last time - the next poll goes straight to it.
    private var resolved: URL?

    /// While the server is unreachable the probe is paused, so a dead address
    /// does not turn into a burst of requests on every poll.
    private var probeBlockedUntil: Date?
    private var failureCount = 0

    public init(endpoint: URL, flavor: StrataFlavor = .automatic) {
        self.endpoint = endpoint
        self.flavor = flavor
    }

    /// Address that is currently used for polling.
    public var activeEndpoint: URL { resolved ?? endpoint }

    // MARK: - Fetching

    /// Monitor data.
    ///
    /// The address that answered is remembered, so the search happens only
    /// once - until the server moves its endpoints again. All candidates are
    /// probed at once: the server may live on another port or under another
    /// path, and waiting for a timeout on each of them would be slow.
    public func fetch() async throws -> MetricsPayload {
        if let resolved {
            if let payload = try? await fetchPayload(at: resolved), payload.isMonitorPayload {
                return payload
            }
            self.resolved = nil
        }
        if let blocked = probeBlockedUntil, blocked > Date() {
            throw ClientError.noMonitorEndpoint
        }
        let candidates = candidateURLs()
        var found: (url: URL, payload: MetricsPayload)?
        await withTaskGroup(of: (URL, MetricsPayload)?.self) { group in
            for url in candidates {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    // Проба идёт с коротким таймаутом: иначе поиск тормозит
                    // на портах, которые никто не слушает.
                    guard let payload = try? await self.fetchPayload(at: url, timeout: 2.5),
                          payload.isMonitorPayload
                    else { return nil }
                    return (url, payload)
                }
            }
            for await result in group {
                if let result {
                    found = result
                    break       // остальные пробы отменяются
                }
            }
        }
        guard let found else {
            failureCount += 1
            let delay = min(pow(2.0, Double(failureCount)) * 2.5, 60)
            probeBlockedUntil = Date().addingTimeInterval(delay)
            throw ClientError.noMonitorEndpoint
        }
        resolved = found.url
        failureCount = 0
        probeBlockedUntil = nil
        return found.payload
    }

    /// Static information of the desktop build: hardware names and the model
    /// catalogue. `nil` when the server has no such endpoints.
    public func fetchStatic() async throws -> StaticInfo? {
        guard flavor != .sourceBuild, let root = apiRoot else { return nil }
        async let hardware = fetchJSON(at: root.appendingPathComponent("hardware"))
        async let models = fetchJSON(at: root.appendingPathComponent("models"))
        let (hardwareJSON, modelsJSON) = await (hardware, models)
        guard let hardwareJSON else { return nil }
        return StaticInfo(hardware: hardwareJSON, models: modelsJSON)
    }

    /// Root of the REST API of the modern build: `http://host:port/api`.
    public var apiRoot: URL? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil
        else { return nil }
        components.path = "/api"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    // MARK: - Candidates

    /// Addresses to try when the configured one does not answer with monitor data.
    func candidateURLs() -> [URL] {
        var result: [URL] = [endpoint]
        let paths = flavor.paths
        for origin in origins() {
            for path in paths {
                guard let url = url(origin: origin, path: path) else { continue }
                if !result.contains(url) { result.append(url) }
            }
        }
        return result
    }

    /// The given origin first, then the same host on the well-known ports.
    ///
    /// The extra ports are tried only in the automatic mode: if the user picked
    /// the installation by hand, we take the address as it is.
    private func origins() -> [URL] {
        var result: [URL] = []
        if let origin = origin(of: endpoint) { result.append(origin) }
        guard flavor == .automatic, let host = endpoint.host else { return result }
        let scheme = endpoint.scheme ?? "http"
        for port in Self.knownPorts where port != endpoint.port {
            if let candidate = URL(string: "\(scheme)://\(host):\(port)") { result.append(candidate) }
        }
        return result
    }

    private func origin(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func url(origin: URL, path: String) -> URL? {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path
        return components.url
    }

    // MARK: - Low level

    private func fetchPayload(at url: URL, timeout: TimeInterval = 5) async throws -> MetricsPayload {
        guard let json = await fetchJSON(at: url, timeout: timeout) else { throw ClientError.emptyBody }
        return MetricsPayload(root: json)
    }

    private func fetchJSON(at url: URL, timeout: TimeInterval = 5) async -> JSON? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard !data.isEmpty else { return nil }
        return try? JSON(data: data)
    }
}
