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
}
