import Foundation

/// Static information of the modern Strata build.
///
/// The monitor payload only carries live numbers, so the names of the GPU and
/// the CPU, the core counts and the parameters of the running model come from
/// two more endpoints: `GET /api/hardware` and `GET /api/models`. They change
/// rarely, so the app reads them once and refreshes them from time to time.
public struct StaticInfo {
    public let hardware: JSON
    public let models: JSON

    public init(hardware: JSON, models: JSON?) {
        self.hardware = hardware
        self.models = models ?? JSON(nil)
    }

    // MARK: - Hardware

    /// "NVIDIA GeForce RTX 4090"
    public var gpuName: String? {
        hardware["gpus"].array.first?["name"].string
            ?? hardware["accelerator"]["label"].string
    }

    /// "13th Gen Intel(R) Core(TM) i9-13900F"
    public var cpuName: String? {
        hardware["cpu"]["model"].string
            ?? hardware["processors"].array.first?["model"].string
    }

    public var cpuCores: Int? { hardware["cpu"]["cores"].int }
    public var cpuThreads: Int? { hardware["cpu"]["threads"].int }
    public var gpuCount: Int { hardware["gpus"].array.count }

    public var memoryTotalGb: Double? { hardware["memory"]["totalGb"].double }
    public var memoryFreeGb: Double? { hardware["memory"]["freeGb"].double }
    public var diskTotalGb: Double? { hardware["disk"]["totalGb"].double }
    public var diskFreeGb: Double? { hardware["disk"]["freeGb"].double }

    /// "cuda", "metal", "cpu"
    public var backend: String? { hardware["accelerator"]["backend"].string }
    public var driver: String? { hardware["gpus"].array.first?["driver"].string }
    public var hostName: String? { hardware["host"]["name"].string }
    public var hostPlatform: String? { hardware["host"]["platform"].string }

    // MARK: - Model

    /// All models the server knows about.
    public var variants: [JSON] { models["variants"].array }

    /// The variant that is loaded right now (or the one that is selected).
    public var loadedVariant: JSON? {
        variant(models["loaded"]) ?? variant(models["current"])
    }

    private func variant(_ value: JSON) -> JSON? {
        if value.isNull { return nil }
        if let id = value.string {
            return models["variants"].array.first { $0["id"].string == id }
        }
        return value.exists ? value : nil
    }

    public var modelName: String? {
        loadedVariant?["label"].string
            ?? loadedVariant?["name"].string
            ?? loadedVariant?["id"].string
    }

    public var modelQuant: String? { loadedVariant?["quant"].string }
    public var modelParams: String? { loadedVariant?["params"].string }
    public var modelFamily: String? { loadedVariant?["family"].string }
    public var modelContextMax: Int? { loadedVariant?["contextMax"].int }
    public var modelExperts: Int? { loadedVariant?["experts"].int }
    public var modelLayers: Int? { loadedVariant?["layerCount"].int }
    public var modelKVPerTokenKb: Double? { loadedVariant?["kvKbPerToken"].double }
    public var modelKVModes: [String] { loadedVariant?["kvModes"].array.compactMap(\.string) ?? [] }
    public var modelHasDraft: Bool? { loadedVariant?["hasDraft"].bool }
}
