import XCTest
@testable import StrataMonitorKit

/// Поиск адреса монитора: приложение должно находить данные у любой установки Strata.
final class MetricsClientTests: XCTestCase {
    private func client(_ address: String, _ flavor: StrataFlavor) -> MetricsClient {
        MetricsClient(endpoint: URL(string: address)!, flavor: flavor)
    }

    func testDesktopFlavorLooksForTheDesktopEndpoint() {
        let candidates = client("http://10.0.0.5:12387", .desktop).candidateURLs().map(\.absoluteString)
        XCTAssertTrue(candidates.contains("http://10.0.0.5:12387/api/monitor"))
        XCTAssertFalse(candidates.contains("http://10.0.0.5:12387/metrics"))
    }

    func testSourceFlavorLooksForTheSourceEndpoint() {
        let candidates = client("http://10.0.0.5:12388", .sourceBuild).candidateURLs().map(\.absoluteString)
        XCTAssertTrue(candidates.contains("http://10.0.0.5:12388/metrics"))
        XCTAssertFalse(candidates.contains("http://10.0.0.5:12388/api/monitor"))
    }

    func testAutomaticFlavorTriesBoth() {
        let candidates = client("http://10.0.0.5:12387", .automatic).candidateURLs().map(\.absoluteString)
        XCTAssertTrue(candidates.contains("http://10.0.0.5:12387/api/monitor"))
        XCTAssertTrue(candidates.contains("http://10.0.0.5:12387/metrics"))
    }

    func testTheOtherWellKnownPortIsTried() {
        // Адрес указан с одного порта, а Strata может слушать на другом.
        let candidates = client("http://10.0.0.5:12388", .automatic).candidateURLs().map(\.absoluteString)
        XCTAssertTrue(candidates.contains("http://10.0.0.5:12387/api/monitor"))
        XCTAssertTrue(candidates.contains("http://10.0.0.5:12387/metrics"))
    }

    func testAnExplicitFlavorKeepsTheGivenPort() {
        // Тип установки выбран руками — значит, и адрес известен точно.
        let candidates = client("http://10.0.0.5:12387", .desktop).candidateURLs().map(\.absoluteString)
        XCTAssertFalse(candidates.contains("http://10.0.0.5:12388/api/monitor"))
    }

    func testTheGivenAddressIsAlwaysTriedFirst() {
        let candidates = client("http://10.0.0.5:9000/custom/path", .automatic).candidateURLs().map(\.absoluteString)
        XCTAssertEqual(candidates.first, "http://10.0.0.5:9000/custom/path")
    }

    func testApiRootOfTheDesktopBuild() {
        XCTAssertEqual(client("http://10.0.0.5:12387", .desktop).apiRoot?.absoluteString,
                       "http://10.0.0.5:12387/api")
        XCTAssertEqual(client("http://10.0.0.5:12387/api/monitor", .desktop).apiRoot?.absoluteString,
                       "http://10.0.0.5:12387/api")
    }

    func testFlavorTitlesAreLocalized() {
        XCTAssertNotEqual(StrataFlavor.automatic.title(language: .russian),
                          StrataFlavor.automatic.title(language: .english))
        XCTAssertEqual(StrataFlavor.allCases.count, 3)
    }

    // MARK: - Host check of Strata Desktop 1.1

    func testLoopbackHostIsOnlyNeededForRemoteAddresses() {
        XCTAssertEqual(MetricsClient.loopbackHost(for: URL(string: "http://10.0.0.5:12387/api/monitor")!),
                       "localhost:12387")
        XCTAssertEqual(MetricsClient.loopbackHost(for: URL(string: "https://strata.lan/api/monitor")!),
                       "localhost")
        XCTAssertNil(MetricsClient.loopbackHost(for: URL(string: "http://localhost:12387/api/monitor")!))
        XCTAssertNil(MetricsClient.loopbackHost(for: URL(string: "http://127.0.0.1:12387/api/monitor")!))
        XCTAssertNil(MetricsClient.loopbackHost(for: URL(string: "http://[::1]:12387/api/monitor")!))
    }

    func testBadHostIsRecognisedByTheErrorCode() {
        XCTAssertTrue(MetricsClient.isBadHost(Data(#"{"error":"Open the local Strata app to use host controls.","code":"bad-host"}"#.utf8)))
        XCTAssertFalse(MetricsClient.isBadHost(Data(#"{"error":"no","code":"bad-origin"}"#.utf8)))
        XCTAssertFalse(MetricsClient.isBadHost(Data("not json".utf8)))
    }

    func testRetriesARequestWithLoopbackHostAfterBadHost() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { request in
            let host = request.value(forHTTPHeaderField: "Host") ?? ""
            if host.hasPrefix("localhost") {
                return (200, Data(#"{"gpus":[{"name":"RTX 4090"}],"cpu":{"model":"i9"}}"#.utf8))
            }
            return (403, Data(#"{"error":"Open the local Strata app to use host controls.","code":"bad-host"}"#.utf8))
        }
        defer { MockURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MetricsClient(endpoint: URL(string: "http://10.0.0.5:12387")!,
                                   flavor: .desktop,
                                   session: session)

        let info = try await client.fetchStatic()

        XCTAssertEqual(info?.gpuName, "RTX 4090")
        XCTAssertTrue(MockURLProtocol.hosts.contains("localhost:12387"))
    }
}

/// URLProtocol that answers requests locally and remembers the `Host` header,
/// so the bad-host fallback can be tested without a live Strata server.
private final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    static var handler: ((URLRequest) -> (Int, Data))?
    private(set) static var hosts: [String] = []

    static func reset() {
        lock.lock()
        handler = nil
        hosts = []
        lock.unlock()
    }

    private static func take(_ request: URLRequest) -> ((URLRequest) -> (Int, Data))? {
        lock.lock()
        defer { lock.unlock() }
        hosts.append(request.value(forHTTPHeaderField: "Host") ?? "")
        return handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.take(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
