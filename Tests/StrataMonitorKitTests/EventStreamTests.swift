import XCTest
@testable import StrataMonitorKit

/// Разбор потока событий `GET /api/events` desktop-версии Strata.
///
/// Живые цифры (фаза, скорость, счётчики запроса) приходят только в этом
/// потоке: в обычных ответах их нет. Внутри события `native` лежат
/// `instances[].metrics` - полный набор метрик движка.
final class EventStreamTests: XCTestCase {
    // MARK: - Разбор кадра

    func testParsesNamedEvent() throws {
        let frame = "event: native\ndata: {\"instances\":[{\"metrics\":{\"live\":{\"state\":\"generating\"}}}]}"
        let parsed = try XCTUnwrap(EventStream.parse(frame: frame))
        XCTAssertEqual(parsed.name, "native")
        XCTAssertEqual(parsed.json["instances"].array.count, 1)
    }

    func testIgnoresCommentFrames() {
        // Сервер начинает поток с комментария - он не событие.
        XCTAssertNil(EventStream.parse(frame: ": connected"))
        XCTAssertNil(EventStream.parse(frame: ""))
    }

    func testJoinsSeveralDataLines() throws {
        let frame = "event: monitor\ndata: {\"phase\":\ndata: \"idle\"}"
        let parsed = try XCTUnwrap(EventStream.parse(frame: frame))
        XCTAssertEqual(parsed.name, "monitor")
        XCTAssertEqual(parsed.json["phase"].string, "idle")
    }

    func testBrokenJSONDoesNotBreakTheStream() {
        XCTAssertNil(EventStream.parse(frame: "event: monitor\ndata: {not json"))
    }

    // MARK: - Метрики движка

    private func metrics() throws -> JSON {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "native-desktop", withExtension: "json", subdirectory: "Fixtures"),
            "native-desktop.json fixture not found"
        )
        let data = try Data(contentsOf: url)
        let root = try JSON(data: data)
        // Событие `native` приходит с метриками внутри экземпляра.
        let instance = try XCTUnwrap(root["instances"].array.first)
        return try XCTUnwrap(instance["metrics"])
    }

    func testReadsLiveNumbers() throws {
        let payload = MetricsPayload(root: try metrics())
        XCTAssertEqual(payload.liveState, "generating")
        XCTAssertEqual(payload.livePhase, "answering")
        XCTAssertTrue(payload.isGenerating)
        XCTAssertEqual(try XCTUnwrap(payload.liveTPS), 109.8)
        XCTAssertEqual(try XCTUnwrap(payload.liveTPSMean), 104.2)
        XCTAssertEqual(try XCTUnwrap(payload.prefillTPSMean), 2644.8)
        XCTAssertEqual(payload.liveGenerated, 5278)
        XCTAssertEqual(payload.liveMaxTokens, 16384)
        XCTAssertEqual(try XCTUnwrap(payload.liveElapsed), 67.5)
        XCTAssertEqual(payload.liveQueued, 1)
    }

    func testReadsEngineAndHardware() throws {
        let payload = MetricsPayload(root: try metrics())
        XCTAssertEqual(payload.model, "qwen3.8-flash-next-iq3_s")
        XCTAssertEqual(payload.modelQuant, "IQ3_S")
        XCTAssertEqual(payload.engineVersion, "0.1.60")
        XCTAssertEqual(payload.contextTokens, 262144)
        XCTAssertEqual(payload.kvQuant, "int8")
        XCTAssertEqual(payload.expertSlots, 6156)
        XCTAssertEqual(payload.expertCacheMiB, 11965)
        XCTAssertEqual(payload.spec, 8)
        XCTAssertEqual(payload.mtpMax, 6)
        XCTAssertEqual(payload.vramFreeMiB, 1694)
        XCTAssertEqual(payload.arenaMiB, 47962)
        XCTAssertEqual(payload.poolWorkers, 15)
        XCTAssertEqual(payload.gpuName, "NVIDIA GeForce RTX 4090")
        XCTAssertEqual(payload.cpuName, "13th Gen Intel(R) Core(TM) i9-13900F")
        XCTAssertEqual(payload.cpuCores, 24)
        XCTAssertEqual(payload.cpuThreads, 32)
        XCTAssertEqual(try XCTUnwrap(payload.gpuUtil), 98)
        XCTAssertEqual(try XCTUnwrap(payload.gpuTemp), 53)
        XCTAssertEqual(try XCTUnwrap(payload.gpuPower), 255.2, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(payload.pcieRxMB), 12.5, accuracy: 0.01)
    }

    func testReadsHistoryTotalsAndRequests() throws {
        let payload = MetricsPayload(root: try metrics())
        XCTAssertEqual(payload.historyTPS.compactMap { $0 }.count, 5)
        XCTAssertEqual(payload.historyGPUTemp.compactMap { $0 }.count, 3)
        XCTAssertEqual(payload.totalRequests, 19)
        XCTAssertEqual(payload.totalPromptTokens, 551216)
        XCTAssertEqual(payload.totalOutputTokens, 70941)
        XCTAssertEqual(payload.totalReusedTokens, 170460)
        XCTAssertNotNil(payload.serverSince)
        XCTAssertEqual(payload.cacheSlots, 4)
        XCTAssertEqual(payload.cacheRequests, 20)
        XCTAssertEqual(payload.cacheRequestsReused, 3)

        let rows = payload.requests
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.outputTokens, 600)
        XCTAssertEqual(row.promptTokens, 80)
        XCTAssertEqual(try XCTUnwrap(row.decodeTPS), 94.6)
        XCTAssertEqual(try XCTUnwrap(row.firstTokenS), 78.256, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(row.draftAcceptance ?? 0), 238.0 / 338.0, accuracy: 0.001)
    }
}
