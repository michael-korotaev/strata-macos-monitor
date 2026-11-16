import XCTest
@testable import StrataMonitorKit

/// Статика desktop-версии: имена железа и каталог моделей.
final class StaticInfoTests: XCTestCase {
    private func info() throws -> StaticInfo {
        let hardwareURL = try XCTUnwrap(
            Bundle.module.url(forResource: "hardware-desktop", withExtension: "json", subdirectory: "Fixtures"))
        let modelsURL = try XCTUnwrap(
            Bundle.module.url(forResource: "models-desktop", withExtension: "json", subdirectory: "Fixtures"))
        let hardware = try JSON(data: Data(contentsOf: hardwareURL))
        let models = try JSON(data: Data(contentsOf: modelsURL))
        return StaticInfo(hardware: hardware, models: models)
    }

    func testReadsHardwareNames() throws {
        let info = try info()
        XCTAssertEqual(info.gpuName, "NVIDIA GeForce RTX 4090")
        XCTAssertEqual(info.cpuName, "13th Gen Intel(R) Core(TM) i9-13900F")
        XCTAssertEqual(info.cpuCores, 24)
        XCTAssertEqual(info.cpuThreads, 32)
        XCTAssertEqual(info.gpuCount, 1)
        XCTAssertEqual(info.backend, "cuda")
    }

    func testReadsTheCatalog() throws {
        let info = try info()
        // Движок остановлен, поэтому загруженной модели нет.
        XCTAssertNil(info.modelName)
        XCTAssertNil(info.modelQuant)
        // Но каталог доступен.
        let first = try XCTUnwrap(info.variants.first)
        XCTAssertEqual(first["quant"].string, "Q4_K_M")
        XCTAssertEqual(first["contextMax"].int, 32768)
        XCTAssertEqual(first["kvModes"].array.compactMap(\.string), ["INT8", "FP16"])
    }

    func testLoadedVariantIsResolvedById() throws {
        // Сервер может вернуть id варианта, а не сам объект.
        let models = JSON([
            "loaded": "qwen3-30b-iq3xxs",
            "variants": [["id": "qwen3-30b-iq3xxs", "quant": "UD-IQ3_XXS", "contextMax": 131072, "experts": 128]]
        ])
        let info = StaticInfo(hardware: JSON(nil), models: models)
        XCTAssertEqual(info.modelQuant, "UD-IQ3_XXS")
        XCTAssertEqual(info.modelContextMax, 131072)
        XCTAssertEqual(info.modelExperts, 128)
    }

    func testNoLoadedVariant() throws {
        let info = StaticInfo(hardware: JSON(nil), models: JSON(["loaded": nil, "current": nil]))
        XCTAssertNil(info.modelName)
        XCTAssertNil(info.modelQuant)
    }
}
