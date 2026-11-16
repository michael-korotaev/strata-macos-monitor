import XCTest
@testable import StrataMonitorKit

/// Разбор ответа `GET /api/monitor` desktop-версии Strata.
///
/// У desktop-версии другая схема: плоские ключи вместо вложенных `live`,
/// `hardware` и так далее. Приложение обязано понимать обе установки.
final class DesktopPayloadTests: XCTestCase {
    private func payload() throws -> MetricsPayload {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "monitor-desktop", withExtension: "json", subdirectory: "Fixtures"),
            "monitor-desktop.json fixture not found"
        )
        let data = try Data(contentsOf: url)
        return MetricsPayload(root: try JSON(data: data))
    }

    func testRecognisesDesktopBuild() throws {
        let payload = try payload()
        XCTAssertTrue(payload.isModern)
        XCTAssertTrue(payload.isMonitorPayload)
    }

    func testReadsPhase() throws {
        let payload = try payload()
        XCTAssertEqual(payload.liveState, "idle")
        XCTAssertEqual(payload.livePhase, "Waiting for a request")
        XCTAssertFalse(payload.isGenerating)
    }

    func testReadsSpeed() throws {
        let payload = try payload()
        XCTAssertEqual(try XCTUnwrap(payload.liveTPS), 0)   // idle: скорость есть, но нулевая
        XCTAssertEqual(try XCTUnwrap(payload.prefillTPSMean), 0)
        XCTAssertEqual(payload.historyTPS.count, 10)
    }

    func testReadsHardwareWithUnits() throws {
        let payload = try payload()
        XCTAssertEqual(try XCTUnwrap(payload.gpuUtil), 1)
        // 19.74 GiB and 24 GiB, converted from the API's gigabytes.
        let vramTotal = Double(try XCTUnwrap(payload.gpuMemTotal)) / 1_073_741_824
        let vramUsed = Double(try XCTUnwrap(payload.gpuMemUsed)) / 1_073_741_824
        XCTAssertEqual(vramTotal, 24, accuracy: 0.01)
        XCTAssertEqual(vramUsed, 19.74, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(payload.gpuTemp), 35.79)
        XCTAssertEqual(try XCTUnwrap(payload.gpuPower), 16.49)
        XCTAssertEqual(try XCTUnwrap(payload.gpuPowerLimit), 300)
        XCTAssertEqual(try XCTUnwrap(payload.cpuUsage), 6)
        let ramTotal = Double(try XCTUnwrap(payload.ramTotal)) / 1_073_741_824
        XCTAssertEqual(ramTotal, 63.83, accuracy: 0.01)
    }

    func testReadsContextAndExperts() throws {
        let payload = try payload()
        XCTAssertEqual(payload.contextTokens, 32768)
        XCTAssertEqual(payload.expertSlots, 64)
        XCTAssertEqual(payload.expertCacheUsed, 0)
    }

    func testReadsTotals() throws {
        let payload = try payload()
        XCTAssertEqual(payload.totalRequests, 0)
        XCTAssertNotNil(payload.serverSince)
        XCTAssertEqual(payload.cacheSource, "unavailable")
        XCTAssertEqual(payload.cacheEnabled, false)
    }

    func testReadsRequests() throws {
        let payload = try payload()
        let rows = payload.requests
        XCTAssertFalse(rows.isEmpty)
        let first = try XCTUnwrap(rows.first)
        XCTAssertNotNil(first.time)                  // ISO 8601: "2026-11-16T22:01:12.177Z"
        XCTAssertEqual(try XCTUnwrap(first.durationS), 70.487, accuracy: 0.001)
        XCTAssertEqual(first.promptTokens, 34741)
        XCTAssertEqual(first.outputTokens, 5438)
        XCTAssertEqual(first.decodeTPS, 86.5)
        XCTAssertEqual(first.model, "iq3_s")
    }

    func testUnknownBuildDoesNotBreakThePanel() throws {
        // Пустой и сломанный ответ не должны ронять разбор.
        let empty = MetricsPayload(root: JSON(nil))
        XCTAssertEqual(empty.liveState, "idle")
        XCTAssertNil(empty.liveTPS)
        XCTAssertFalse(empty.isMonitorPayload)

        let broken = MetricsPayload(root: JSON(["phase": 42, "outputTps": "fast"]))
        XCTAssertEqual(broken.liveState, "idle")
        XCTAssertNil(broken.liveTPS)
    }

    func testFindsSpeedInAnUnknownSchema() throws {
        // Схема, которую мы не знаем, но скорость в ней называется так же.
        let unknown = MetricsPayload(root: JSON([
            "state": "generating",
            "speed": ["decode_tok_s": 42.5]
        ]))
        XCTAssertEqual(unknown.liveState, "generating")
        XCTAssertEqual(unknown.liveTPS, 42.5)
    }
}
