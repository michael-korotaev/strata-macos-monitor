import Foundation

/// Snapshot of the Strata server state, assembled from `GET /metrics`.
///
/// Fields mirror a real server response (engine 0.1.59), but are read
/// through the JSON wrapper: the server may add a field or change a type and it
/// must not take the monitor down.
public struct MetricsPayload {
    public let root: JSON

    public init(root: JSON) { self.root = root }

    // MARK: - Live (current generation)

    public var liveState: String { root["live"]["state"].string ?? "idle" }
    public var livePhase: String? { root["live"]["phase"].string }
    public var liveQueued: Int { root["live"]["queued"].int ?? 0 }
    public var liveGenerated: Int? { root["live"]["generated"].int }
    public var liveMaxTokens: Int? { root["live"]["max_tokens"].int }
    public var livePromptTokens: Int? { root["live"]["prompt_tokens"].int }
    public var liveElapsed: Double? { root["live"]["elapsed_s"].double }
    /// Decode speed over the 2 s window - a live number while generating.
    public var liveTPS: Double? { root["live"]["tok_s"].double }
    /// Average decode speed of the current request.
    public var liveTPSMean: Double? { root["live"]["tok_s_mean"].double }
    public var prefillTPSMean: Double? { root["live"]["prefill_tok_s_mean"].double }

    public var isGenerating: Bool { liveState == "generating" || liveState == "prefill" }

    // MARK: - Hardware (refreshed on every poll)

    public var gpuUtil: Double? { root["hardware"]["gpu_util"].double }
    public var gpuMemUsed: Int64? { root["hardware"]["gpu_mem_used"].int.map(Int64.init) }
    public var gpuMemTotal: Int64? { root["hardware"]["gpu_mem_total"].int.map(Int64.init) }
    public var gpuTemp: Double? { root["hardware"]["gpu_temp"].double }
    public var gpuPower: Double? { root["hardware"]["gpu_power"].double }
    public var gpuPowerLimit: Double? { root["hardware"]["gpu_power_limit"].double }
    public var pcieRxMB: Double? { root["hardware"]["gpu_pcie_rx_mb"].double }
    public var pcieTxMB: Double? { root["hardware"]["gpu_pcie_tx_mb"].double }
    public var cpuUsage: Double? { root["hardware"]["cpu"].double }
    public var ramUsed: Int64? { root["hardware"]["ram_used"].int.map(Int64.init) }
    public var ramTotal: Int64? { root["hardware"]["ram_total"].int.map(Int64.init) }
    public var diskReadMB: Double? { root["hardware"]["disk_read_mb"].double }
    public var diskWriteMB: Double? { root["hardware"]["disk_write_mb"].double }
    /// Rolling decode speed - shows the card is alive even while idle.
    public var hardwareTPS: Double? { root["hardware"]["tok_s"].double }
    public var hardwareTPSMean: Double? { root["hardware"]["tok_s_mean"].double }
    public var hardwarePrefillTPSMean: Double? { root["hardware"]["prefill_tok_s_mean"].double }

    // MARK: - Static hardware

    public var gpuName: String? { root["hardware_static"]["gpu_name"].string }
    public var cpuName: String? { root["hardware_static"]["cpu_name"].string }
    public var cpuCores: Int? { root["hardware_static"]["cores"].int }
    public var cpuThreads: Int? { root["hardware_static"]["threads"].int }
    public var gpuCount: Int? { root["hardware_static"]["gpu_count"].int }

    // MARK: - Engine

    public var model: String? { root["engine"]["model"].string }
    public var engineVersion: String? { root["engine"]["version"].string }
    public var contextTokens: Int? { root["engine"]["context"].int ?? root["engine"]["max_context"].int }
    public var kvQuant: String? { root["engine"]["kv"].string }
    public var kvResident: Int? { root["engine"]["kv_resident"].int }
    public var expertSlots: Int? { root["engine"]["expert_slots"].int }
    public var expertCacheMiB: Int? { root["engine"]["expert_cache_mib"].int }
    public var spec: Int? { root["engine"]["spec"].int }
    public var mtpMax: Int? { root["engine"]["mtp_max"].int }
    public var drafting: String? { root["engine"]["drafting"].string }
    public var vramFreeMiB: Int? { root["engine"]["vram_free_mib"].int }
    public var arenaMiB: Int? { root["engine"]["arena_mib"].int }
    public var poolWorkers: Int? { root["engine"]["pool_workers"].int }
    public var pcieFrac: Double? { root["engine"]["pcie_frac"].double }
    public var prefillCap: Int? { root["engine"]["prefill_cap"].int }
    public var conversationCacheMiB: Int? { root["engine"]["conversation_cache_mib"].int }
    public var conversationCacheSlots: Int? { root["engine"]["conversation_cache_slots"].int }

    // MARK: - Totals

    public var totalRequests: Int? { root["totals"]["requests"].int }
    public var totalPromptTokens: Int64? { root["totals"]["prompt_tokens"].int.map(Int64.init) }
    public var totalReusedTokens: Int64? { root["totals"]["reused"].int.map(Int64.init) }
    public var totalOutputTokens: Int64? { root["totals"]["output_tokens"].int.map(Int64.init) }
    public var totalDecodeMs: Double? { root["totals"]["decode_ms"].double }
    public var totalDraftsOffered: Int? { root["totals"]["drafts_offered"].int }
    public var totalDraftsAccepted: Int? { root["totals"]["drafts_accepted"].int }
    public var serverSince: Double? { root["totals"]["since"].double }

    // MARK: - Conversation cache

    public var cacheEnabled: Bool? { root["conversation_cache"]["enabled"].bool }
    public var cacheSlots: Int? { root["conversation_cache"]["slots"].int }
    public var cacheParked: Int? { root["conversation_cache"]["parked"].int }
    public var cacheRequests: Int? { root["conversation_cache"]["requests"].int }
    public var cacheRequestsReused: Int? { root["conversation_cache"]["requests_reused"].int }
    public var cacheReusedTokens: Int64? { root["conversation_cache"]["reused_tokens"].int.map(Int64.init) }
    public var cachePromptTokens: Int64? { root["conversation_cache"]["prompt_tokens"].int.map(Int64.init) }
    public var cacheEvictions: Int? { root["conversation_cache"]["evictions"].int }

    // MARK: - History (60 samples, ~1 Hz)

    public var historyTPS: [Double?] { root["history"]["tok_s"].doubles }
    public var historyGPUUtil: [Double?] { root["history"]["gpu_util"].doubles }
    public var historyGPUTemp: [Double?] { root["history"]["gpu_temp"].doubles }
    public var historyGPUPower: [Double?] { root["history"]["gpu_power"].doubles }
    public var historyPrefillTPS: [Double?] { root["history"]["prefill_tok_s_mean"].doubles }

    // MARK: - Requests

    public var requests: [RequestRow] { root["requests"].array.map(RequestRow.init) }
    public var requestsKept: Int? { root["requests_kept"].int }

    /// One finished generation.
    public struct RequestRow {
        public let json: JSON

        public init(json: JSON) { self.json = json }

        public var id: String { json["id"].string ?? "—" }
        public var time: Date? { json["time"].double.map { Date(timeIntervalSince1970: $0) } }
        public var durationS: Double? { json["duration_s"].double }
        public var finish: String? { json["finish"].string }
        public var promptTokens: Int? { json["prompt_tokens"].int }
        public var reusedTokens: Int? { json["reused"].int }
        public var outputTokens: Int? { json["output_tokens"].int }
        public var firstTokenS: Double? { json["first_engine_token_s"].double }
        public var promptMs: Double? { json["prompt_ms"].double }
        public var decodeMs: Double? { json["decode_ms"].double }
        public var decodeTPS: Double? { json["decode_tok_s"].double }
        public var hitRate: Double? { json["hit_rate"].double }
        public var pcieShare: Double? { json["pcie_share"].double }
        public var draftsOffered: Int? { json["drafts_offered"].int }
        public var draftsAccepted: Int? { json["drafts_accepted"].int }

        /// Share of accepted drafts (speculative decoding).
        public var draftAcceptance: Double? {
            guard let offered = draftsOffered, offered > 0, let accepted = draftsAccepted else { return nil }
            return Double(accepted) / Double(offered)
        }
    }
}
