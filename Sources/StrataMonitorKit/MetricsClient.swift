import Foundation

/// HTTP client for Strata.
///
/// The server moves its endpoints between builds, so the client does not
/// insist on one exact URL: it remembers the address that worked and, when it
/// stops working, looks for the monitor endpoint again - the same host on the
/// known ports, the known paths on each of them.
///
/// The desktop application keeps the live numbers (phase, tokens/s, the
/// counters of the running request) out of its HTTP responses: they only come
/// through the event stream `GET /api/events`, in the `native` event
/// (`instances[].metrics`). A source build has everything in `GET /metrics`,
/// so it is polled as usual.
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

    /// How long a payload may be used before it counts as stale.
    private static let freshInterval: TimeInterval = 3

    public let endpoint: URL

    /// Which Strata installation is expected on the other side.
    public let flavor: StrataFlavor

    /// Address that answered last time - the next poll goes straight to it.
    private var resolved: URL?

    /// While the server is unreachable the probe is paused, so a dead address
    /// does not turn into a burst of requests on every poll.
    private var probeBlockedUntil: Date?
    private var failureCount = 0

    /// Origins that answered `403 bad-host`: the desktop application checks
    /// the `Host` header and accepts only loopback names, so from now on the
    /// requests to those origins carry `Host: localhost:<port>`.
    private let hostLock = NSLock()
    private var loopbackHostOrigins: Set<String> = []

    /// Session for plain HTTP requests (injectable for tests).
    private let session: URLSession

    // MARK: - Event stream

    /// The stream itself.
    private var stream: EventStream?
    /// Reads the stream and fills the payload fields below.
    private var streamTask: Task<Void, Never>?
    /// `nil` - not decided yet, `true` - the event stream, `false` - plain polling.
    private var useStream: Bool?

    /// The first stream attempt happens before the desktop host check is known.
    /// After the HTTP probe learns it, the stream is retried once at once.
    private var streamRetriedAfterHostCheck = false

    /// The state of the stream. It is written by the reader task and read by
    /// the polling task, so it is guarded by a lock.
    private let lock = NSLock()
    private var streamState = StreamState()

    /// The state of the stream.
    private struct StreamState {
        /// Live metrics of the engine (`native` event): the phase, the speed
        /// and the counters of the running request.
        var enginePayload: MetricsPayload?
        var engineAt: Date?
        /// State of the control layer (`monitor` event): the fallback for the
        /// moments when the engine is stopped.
        var monitorPayload: MetricsPayload?
        var monitorAt: Date?
        /// The server sent the `native` event at least once.
        var nativeEventSeen = false
        /// The stream was closed by the server.
        var streamEnded = false
    }

    public convenience init(endpoint: URL, flavor: StrataFlavor = .automatic) {
        self.init(endpoint: endpoint, flavor: flavor, session: .shared)
    }

    init(endpoint: URL, flavor: StrataFlavor = .automatic, session: URLSession) {
        self.endpoint = endpoint
        self.flavor = flavor
        self.session = session
    }

    /// Address that is currently used for polling.
    public var activeEndpoint: URL { resolved ?? endpoint }

    /// The live data comes from the event stream - that is the desktop build.
    public var usesEventStream: Bool { useStream == true }

    // MARK: - Fetching

    /// Monitor data.
    ///
    /// The address that answered is remembered, so the search happens only
    /// once - until the server moves its endpoints again. All candidates are
    /// probed at once: the server may live on another port or under another
    /// path, and waiting for a timeout on each of them would be slow.
    public func fetch() async throws -> MetricsPayload {
        if flavor == .sourceBuild {
            useStream = false
        } else if useStream == nil {
            // The desktop application reports the live numbers only through the
            // event stream; a source build has no such endpoint.
            useStream = await startStream()
        }
        if useStream == true {
            // Two attempts: the first one may hit a stream closed by a restart
            // of the server, the second one opens a fresh stream.
            for _ in 0..<2 {
                if let payload = try? await fetchFromStream() { return payload }
                resetStream()
                guard await startStream() else { break }
            }
            useStream = nil
        }
        let payload = try await fetchOverHTTP()
        // Сервер ответил плоской схемой - значит, это desktop-сборка, а она
        // отдаёт живые цифры только через поток событий. Если поток не
        // открылся (сервер был выключен при старте), пробуем ещё раз.
        let hostCheckKnown = useStream == false
            && !streamRetriedAfterHostCheck
            && (eventsURL.map { needsLoopbackHost(for: $0) } ?? false)
        if flavor == .automatic, payload.isModern, shouldRetryStream() || hostCheckKnown {
            if hostCheckKnown { streamRetriedAfterHostCheck = true }
            useStream = await startStream()
        }
        return payload
    }

    /// Когда последний раз пробовали открыть поток.
    private var lastStreamAttempt: Date?

    /// Пора ли открыть поток ещё раз (раз в минуту).
    private func shouldRetryStream() -> Bool {
        guard let last = lastStreamAttempt else { return true }
        return Date().timeIntervalSince(last) > 60
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

    /// Root of the REST API of the desktop build: `http://host:port/api`.
    public var apiRoot: URL? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil
        else { return nil }
        components.path = "/api"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// URL of the event stream: `http://host:port/api/events`.
    public var eventsURL: URL? {
        apiRoot?.appendingPathComponent("events")
    }

    // MARK: - Event stream

    /// Opens the event stream. Returns `false` when the server has no such
    /// endpoint (that is, when it is a source build).
    private func startStream() async -> Bool {
        guard let url = eventsURL else { return false }
        lastStreamAttempt = Date()
        // После первого `403 bad-host` поток тоже открывается с loopback-Host:
        // проверка Strata смотрит на заголовок, а не на адрес, куда пришёл запрос.
        let host = needsLoopbackHost(for: url) ? Self.loopbackHost(for: url) : nil
        let stream = EventStream(url: url, hostHeader: host)
        self.stream = stream
        setStreamState { state in
            state.nativeEventSeen = false
            state.streamEnded = false
        }

        streamTask = Task { [weak self] in
            for await event in stream.events() {
                // Клиент мог быть освобождён (сменился адрес) - тогда поток
                // закрываем, иначе соединение с сервером останется висеть.
                guard let self else { return }
                self.handle(event)
            }
            self?.setStreamState { $0.streamEnded = true }
        }

        // Ждём заголовки ответа: заодно выясняется, есть ли поток у сервера.
        let headerDeadline = Date().addingTimeInterval(3)
        while Date() < headerDeadline, stream.response == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard stream.isEventStream else {
            resetStream()
            return false
        }
        // Первое событие `native` несёт живые метрики движка: ждём его,
        // иначе панель покажет «idle», пока поток не наберёт следующий кадр.
        let nativeDeadline = Date().addingTimeInterval(4)
        while Date() < nativeDeadline {
            if hasNativeEvent() { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }

    /// Handles one event of the stream.
    private func handle(_ event: EventStream.Event) {
        switch event {
        case .named("native", let json):
            // Метрики движка: полный набор, включая живую скорость.
            let metrics = json["instances"].array.first?["metrics"]
            setStreamState { state in
                state.nativeEventSeen = true
                guard let metrics, metrics.exists else {
                    // Движок не запущен - остаются данные слоя управления.
                    state.enginePayload = nil
                    state.engineAt = nil
                    return
                }
                state.enginePayload = MetricsPayload(root: metrics)
                state.engineAt = Date()
            }
        case .named("monitor", let json):
            // Запасной вариант: состояние слоя управления.
            setStreamState { state in
                state.monitorPayload = MetricsPayload(root: json)
                state.monitorAt = Date()
            }
        default:
            break
        }
    }

    /// The freshest payload: the metrics of the engine are preferred.
    private func currentPayload() -> MetricsPayload? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let engine = streamState.enginePayload, let at = streamState.engineAt,
           now.timeIntervalSince(at) < Self.freshInterval {
            return engine
        }
        if let monitor = streamState.monitorPayload, let at = streamState.monitorAt,
           now.timeIntervalSince(at) < Self.freshInterval {
            return monitor
        }
        return nil
    }

    private func hasNativeEvent() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return streamState.nativeEventSeen
    }

    private func setStreamState(_ change: (inout StreamState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&streamState)
    }

    /// Waits for the next payload of the stream.
    private func fetchFromStream(timeout: TimeInterval = 4) async throws -> MetricsPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let payload = currentPayload() { return payload }
            if isStreamEnded() { throw ClientError.emptyBody }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ClientError.emptyBody
    }

    private func isStreamEnded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return streamState.streamEnded
    }

    /// Closes the stream and forgets what it brought.
    private func resetStream() {
        streamTask?.cancel()
        streamTask = nil
        stream?.stop()
        stream = nil
        setStreamState { state in
            state.enginePayload = nil
            state.engineAt = nil
            state.monitorPayload = nil
            state.monitorAt = nil
            state.nativeEventSeen = false
            state.streamEnded = false
        }
    }

    // MARK: - Plain polling

    private func fetchOverHTTP() async throws -> MetricsPayload {
        if let resolved {
            if let payload = try? await fetchPayload(at: resolved), payload.isMonitorPayload {
                return payload
            }
            self.resolved = nil
        }
        if let payload = try? await fetchPayload(at: endpoint), payload.isMonitorPayload {
            resolved = endpoint
            return payload
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
        if needsLoopbackHost(for: url), let host = Self.loopbackHost(for: url) {
            request.setValue(host, forHTTPHeaderField: "Host")
        }
        guard var result = await perform(request) else { return nil }
        // Strata Desktop 1.1: проверка Host отвечает 403 `bad-host` на любой
        // адрес, кроме loopback. Повторяем запрос с `Host: localhost:<port>`
        // и запоминаем, что этому серверу нужен такой заголовок.
        if result.status == 403, Self.isBadHost(result.data), let host = Self.loopbackHost(for: url) {
            rememberLoopbackHost(for: url)
            request.setValue(host, forHTTPHeaderField: "Host")
            guard let retried = await perform(request) else { return nil }
            result = retried
        }
        guard (200..<300).contains(result.status), !result.data.isEmpty else { return nil }
        return try? JSON(data: result.data)
    }

    private struct HTTPResult {
        let status: Int
        let data: Data
    }

    private func perform(_ request: URLRequest) async -> HTTPResult? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        return HTTPResult(status: http.statusCode, data: data)
    }

    // MARK: - Host check of the desktop build

    /// The `Host` header Strata Desktop accepts for `/api/*` from another
    /// computer. Its request guard allows only `localhost`, `127.x.x.x` and
    /// `[::1]`, so a remote address gets `403 bad-host` even though the
    /// request arrived at that address. `nil` when no override is needed.
    static func loopbackHost(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !isLoopbackName(host) else { return nil }
        guard let port = url.port else { return "localhost" }
        return "localhost:\(port)"
    }

    static func isLoopbackName(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }

    /// The server refused the request because of the `Host` header.
    static func isBadHost(_ data: Data) -> Bool {
        (try? JSON(data: data))?["code"].string == "bad-host"
    }

    private func needsLoopbackHost(for url: URL) -> Bool {
        guard let key = origin(of: url)?.absoluteString else { return false }
        hostLock.lock()
        defer { hostLock.unlock() }
        return loopbackHostOrigins.contains(key)
    }

    private func rememberLoopbackHost(for url: URL) {
        guard let key = origin(of: url)?.absoluteString else { return }
        hostLock.lock()
        loopbackHostOrigins.insert(key)
        hostLock.unlock()
    }
}
