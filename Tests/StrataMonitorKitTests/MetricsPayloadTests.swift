import XCTest
@testable import StrataMonitorKit

/// Разбор реального ответа `GET /metrics` сервера Strata.
final class MetricsPayloadTests: XCTestCase {
    private func fixture() throws -> MetricsPayload {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "metrics", withExtension: "json")
                ?? Bundle.module.url(forResource: "metrics", withExtension: "json", subdirectory: "Fixtures"),
            "metrics.json fixture not found"
        )
        let data = try Data(contentsOf: url)
        return MetricsPayload(root: try JSON(data: data))
    }

    func testReadsLiveGeneration() throws {
        let payload = try fixture()
        XCTAssertEqual(payload.liveState, "generating")
        XCTAssertTrue(payload.isGenerating)
        XCTAssertEqual(payload.liveTPS, 177.2)
        XCTAssertEqual(payload.liveGenerated, 245)
        XCTAssertEqual(payload.liveMaxTokens, 16384)
        XCTAssertEqual(payload.prefillTPSMean, 241.0)
        XCTAssertEqual(payload.livePhase, "writing a tool call: edit")
    }

    func testReadsHardware() throws {
        let payload = try fixture()
        XCTAssertEqual(payload.gpuName, "NVIDIA GeForce RTX 4090")
        XCTAssertNotNil(payload.gpuUtil)
        XCTAssertNotNil(payload.gpuMemUsed)
        XCTAssertNotNil(payload.gpuMemTotal)
        XCTAssertNotNil(payload.gpuTemp)
        XCTAssertNotNil(payload.gpuPower)
        XCTAssertNotNil(payload.cpuUsage)
        XCTAssertNotNil(payload.ramUsed)
    }

    func testReadsEngineAndTotals() throws {
        let payload = try fixture()
        XCTAssertEqual(payload.model, "qwen3.8-flash-next-iq2_xs")
        XCTAssertEqual(payload.engineVersion, "0.1.59")
        XCTAssertEqual(payload.contextTokens, 262_144)
        XCTAssertEqual(payload.kvQuant, "int8")
        XCTAssertNotNil(payload.totalRequests)
        XCTAssertNotNil(payload.totalOutputTokens)
        XCTAssertNotNil(payload.cacheRequests)
    }

    func testReadsRequests() throws {
        let payload = try fixture()
        let requests = payload.requests
        XCTAssertEqual(requests.count, 3)
        let first = try XCTUnwrap(requests.first)
        XCTAssertNotNil(first.decodeTPS)
        XCTAssertNotNil(first.firstTokenS)
        XCTAssertNotNil(first.durationS)
        if let acceptance = first.draftAcceptance {
            XCTAssertGreaterThan(acceptance, 0)
            XCTAssertLessThanOrEqual(acceptance, 1)
        }
    }

    func testHistoryHasSamples() throws {
        let payload = try fixture()
        XCTAssertGreaterThan(payload.historyTPS.compactMap { $0 }.count, 10)
        XCTAssertGreaterThan(payload.historyGPUUtil.compactMap { $0 }.count, 10)
    }

    /// Сервер может поменять схему — монитор не должен на этом падать.
    func testEmptyAndBrokenPayloadAreSafe() throws {
        let empty = MetricsPayload(root: try JSON(data: Data("{}".utf8)))
        XCTAssertNil(empty.model)
        XCTAssertNil(empty.gpuUtil)
        XCTAssertNil(empty.liveTPS)
        XCTAssertFalse(empty.isGenerating)
        XCTAssertTrue(empty.requests.isEmpty)
        XCTAssertTrue(empty.historyTPS.isEmpty)

        let broken = MetricsPayload(root: try JSON(data: Data("{\"live\": \"нет\"}".utf8)))
        XCTAssertNil(broken.liveTPS)
        XCTAssertEqual(broken.liveState, "idle")
    }
}
