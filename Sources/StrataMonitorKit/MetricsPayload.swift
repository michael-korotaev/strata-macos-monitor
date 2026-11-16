import Foundation

/// Snapshot of the Strata server state.
///
/// Two server generations are supported:
///
/// - **modern** — `GET /api/monitor`: a flat JSON with `phase`, `outputTps`,
///   `hardware`, `history` and `requests`.
/// - **legacy** — `GET /metrics`: the same data under `live`, `hardware`,
///   `history.tok_s` and so on.
///
/// Every field is read defensively through the JSON wrapper: the server may
/// add a field or change a type and it must not take the monitor down. New
/// fields are read first, the legacy ones are the fallback.
public struct MetricsPayload {
    public let root: JSON

    public init(root: JSON) { self.root = root }

    /// Modern build (`/api/monitor`) rather than the legacy one (`/metrics`).
    public var isModern: Bool {
        root["phase"].string != nil
            || root["outputTps"].double != nil
            || root["hardware"]["gpus"].array.isEmpty == false
            || root["context"]["maxTokens"].int != nil
    }

    /// The answer looks like monitor data (and not like the web UI page).
    public var isMonitorPayload: Bool {
        if isModern { return true }
        if root["live"]["state"].string != nil { return true }
        if root["hardware"]["gpu_util"].double != nil { return true }
        return false
    }

    // MARK: - Live (current generation)

    /// Server phase: `idle`, `reading`, `generating`, `loading`, `starting`…
    public var liveState: String {
        if let phase = root["phase"].string, Self.looksLikePhase(phase) { return phase }
        if let state = root["live"]["state"].string { return state }
        return heuristicPhase ?? "idle"
    }

    /// A phase is a word, not a number: a field of another type must not be
    /// taken for a phase.
    private static func looksLikePhase(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard Double(text) == nil else { return false }
        return text.allSatisfy { $0.isLetter || $0 == "_" }
    }

    /// Phase found by name, for a server build with a schema we do not know.
    private var heuristicPhase: String? {
        for name in ["phase", "state", "status"] {
            guard let value = root[name].string else { continue }
            if Self.knownPhases.contains(value) { return value }
        }
        for name in ["phase", "state"] {
            guard let value = root.first(where: name)?.string else { continue }
            if Self.knownPhases.contains(value) { return value }
        }
        return nil
    }

    private static let knownPhases: Set<String> = [
        "idle", "ready", "loading", "starting", "queued", "waiting",
        "reading", "generating", "thinking", "decision", "checkpointing",
        "checking", "complete", "paused", "cancelled", "failed", "interrupted"
    ]

    /// Human readable phase from the server (English).
    public var livePhase: String? {
        root["phaseLabel"].string ?? root["live"]["phase"].string
    }

    /// Requests waiting in the queue.
    public var liveQueued: Int {
        root["queue"]["waiting"].int ?? root["live"]["queued"].int ?? 0
    }

    /// Tokens generated so far.
    public var liveGenerated: Int? {
        root["generation"]["done"].int ?? root["live"]["generated"].int
    }

    /// Token budget of the running request.
    public var liveMaxTokens: Int? {
        root["generation"]["total"].int ?? root["live"]["max_tokens"].int
    }

    /// Prompt size of the running request.
    public var livePromptTokens: Int? {
        root["prompt"]["total"].int ?? root["live"]["prompt_tokens"].int
    }

    /// Seconds since the request started.
    public var liveElapsed: Double? {
        root["live"]["elapsed_s"].double
    }

    /// Decode speed over the last window - a live number while generating.
    public var liveTPS: Double? {
        if let tps = root["outputTps"].double { return tps }
        if let tps = root["live"]["tok_s"].double { return tps }
        return heuristicSpeed
    }

    /// Decode speed found by key name, for a server build we do not know.
    private var heuristicSpeed: Double? {
        for name in ["outputTps", "tok_s", "decode_tok_s", "tps", "tokensPerSecond", "decodeSpeed"] {
            guard let value = root.first(where: name)?.double, value > 0 else { continue }
            return value
        }
        return nil
    }

    /// Average decode speed of the current request.
    public var liveTPSMean: Double? {
        root["live"]["tok_s_mean"].double
    }

    /// Prompt read speed (prefill).
    public var prefillTPSMean: Double? {
        if let tps = root["promptTps"].double { return tps }
        return root["live"]["prefill_tok_s_mean"].double
    }

    /// The engine is working on a request right now.
    public var isGenerating: Bool {
        switch liveState {
        case "generating", "reading", "prefill", "thinking", "decision", "checkpointing": return true
        default: return false
        }
    }

    // MARK: - Hardware (refreshed on every poll)

    public var gpuUtil: Double? {
        root["hardware"]["gpuLoad"].double ?? root["hardware"]["gpu_util"].double
    }

    public var gpuMemUsed: Int64? {
        if let gib = root["hardware"]["vramUsedGb"].double { return Int64(gib * 1_073_741_824) }
        return root["hardware"]["gpu_mem_used"].int.map(Int64.init)
    }

    public var gpuMemTotal: Int64? {
        if let gib = root["hardware"]["vramTotalGb"].double { return Int64(gib * 1_073_741_824) }
        return root["hardware"]["gpu_mem_total"].int.map(Int64.init)
    }

    public var gpuTemp: Double? {
        root["hardware"]["gpuTempC"].double ?? root["hardware"]["gpu_temp"].double
    }

    public var gpuPower: Double? {
        root["hardware"]["powerW"].double ?? root["hardware"]["gpu_power"].double
    }

    public var gpuPowerLimit: Double? {
        root["hardware"]["powerLimitW"].double ?? root["hardware"]["gpu_power_limit"].double
    }

    public var pcieRxMB: Double? {
        root["hardware"]["pcieRxMbs"].double ?? root["hardware"]["gpu_pcie_rx_mb"].double
    }

    public var pcieTxMB: Double? {
        root["hardware"]["pcieTxMbs"].double ?? root["hardware"]["gpu_pcie_tx_mb"].double
    }

    public var cpuUsage: Double? {
        root["hardware"]["cpuLoad"].double ?? root["hardware"]["cpu"].double
    }

    public var ramUsed: Int64? {
        if let gib = root["hardware"]["ramUsedGb"].double { return Int64(gib * 1_073_741_824) }
        return root["hardware"]["ram_used"].int.map(Int64.init)
    }

    public var ramTotal: Int64? {
        if let gib = root["hardware"]["ramTotalGb"].double { return Int64(gib * 1_073_741_824) }
        return root["hardware"]["ram_total"].int.map(Int64.init)
    }

    public var diskReadMB: Double? {
        if let gbs = root["hardware"]["diskReadGbs"].double { return gbs * 1024 }   // GB/s -> MB/s
        return root["hardware"]["disk_read_mb"].double
    }

    public var diskWriteMB: Double? {
        root["hardware"]["diskWriteMbs"].double ?? root["hardware"]["disk_write_mb"].double
    }

    /// Rolling decode speed - shows the card is alive even while idle.
    public var hardwareTPS: Double? {
        if let tps = root["hardware"]["tok_s"].double { return tps }
        return historyTPS.compactMap { $0 }.last
    }

    public var hardwareTPSMean: Double? {
        root["hardware"]["tok_s_mean"].double
    }

    public var hardwarePrefillTPSMean: Double? {
        root["hardware"]["prefill_tok_s_mean"].double
    }

    // MARK: - Static hardware (legacy build only)

    public var gpuName: String? { root["hardware_static"]["gpu_name"].string }
    public var cpuName: String? { root["hardware_static"]["cpu_name"].string }
    public var cpuCores: Int? { root["hardware_static"]["cores"].int }
    public var cpuThreads: Int? { root["hardware_static"]["threads"].int }
    public var gpuCount: Int? { root["hardware_static"]["gpu_count"].int }

    // MARK: - Engine

    public var model: String? {
        root["engine"]["modelId"].string ?? root["engine"]["model"].string
    }

    public var engineVersion: String? { root["engine"]["version"].string }

    /// Quantization of the running model.
    ///
    /// The server does not report it separately, but the model id ends with
    /// it: `qwen3.8-flash-next-iq3_s` -> `IQ3_S`.
    public var modelQuant: String? {
        guard let model, let separator = model.lastIndex(of: "-") else { return nil }
        let tail = String(model[model.index(after: separator)...])
        guard !tail.isEmpty, tail.count <= 8, tail.contains(where: \.isNumber) else { return nil }
        return tail.uppercased()
    }

    /// Context window of the running model.
    public var contextTokens: Int? {
        root["context"]["maxTokens"].int
            ?? root["engine"]["context"].int
            ?? root["engine"]["max_context"].int
    }

    /// Tokens in the context right now.
    public var contextUsedTokens: Int? { root["context"]["usedTokens"].int }

    /// KV cache format (legacy build).
    public var kvQuant: String? { root["engine"]["kv"].string }
    public var kvResident: Int? { root["engine"]["kv_resident"].int }
    public var expertSlots: Int? { root["expertCache"]["total"].int ?? root["engine"]["expert_slots"].int }
    public var expertCacheUsed: Int? { root["expertCache"]["used"].int }
    public var expertCacheMiB: Int? { root["engine"]["expert_cache_mib"].int }
    public var spec: Int? { root["engine"]["spec"].int }
    public var mtpMax: Int? { root["engine"]["mtp_max"].int }
    public var drafting: String? { root["engine"]["drafting"].string }
    public var vramFreeMiB: Int? { root["engine"]["vram_free_mib"].int }
    public var arenaMiB: Int? { root["engine"]["arena_mib"].int }
    public var poolWorkers: Int? { root["engine"]["pool_workers"].int }
    public var prefillCap: Int? { root["engine"]["prefill_cap"].int }
    public var conversationCacheMiB: Int? { root["engine"]["conversation_cache_mib"].int }
    public var conversationCacheSlots: Int? { root["engine"]["conversation_cache_slots"].int }

    // MARK: - Totals

    public var totalRequests: Int? { root["totals"]["requests"].int }
    public var totalPromptTokens: Int64? {
        root["totals"]["tokensIn"].int.map(Int64.init) ?? root["totals"]["prompt_tokens"].int.map(Int64.init)
    }
    public var totalReusedTokens: Int64? {
        root["totals"]["cachedTokens"].int.map(Int64.init) ?? root["totals"]["reused"].int.map(Int64.init)
    }
    public var totalUncachedTokens: Int64? { root["totals"]["uncachedTokens"].int.map(Int64.init) }
    public var totalOutputTokens: Int64? {
        root["totals"]["tokensOut"].int.map(Int64.init) ?? root["totals"]["output_tokens"].int.map(Int64.init)
    }
    public var totalDecodeMs: Double? { root["totals"]["decode_ms"].double }
    /// Average decode speed over the session.
    public var totalAvgTPS: Double? { root["totals"]["avgTps"].double }
    /// Average time to the first token.
    public var totalTTFTMs: Double? { root["totals"]["ttftMs"].double }
    public var totalDraftsOffered: Int? { root["totals"]["drafts_offered"].int }
    public var totalDraftsAccepted: Int? { root["totals"]["drafts_accepted"].int }

    /// Session start: a date in the modern build, a unix timestamp in the legacy one.
    public var serverSince: Date? {
        if let date = ISO.date(root["totals"]["since"].string) { return date }
        return root["totals"]["since"].double.map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - Conversation cache

    /// Where the conversation cache comes from; `unavailable` when there is none.
    public var cacheSource: String? { root["conversationCache"]["source"].string }

    public var cacheEnabled: Bool? {
        if let source = cacheSource { return source != "unavailable" }
        return root["conversation_cache"]["enabled"].bool
    }
    public var cacheSlots: Int? { root["conversation_cache"]["slots"].int }
    public var cacheParked: Int? { root["conversation_cache"]["parked"].int }
    public var cacheRequests: Int? { root["conversation_cache"]["requests"].int }
    public var cacheRequestsReused: Int? { root["conversation_cache"]["requests_reused"].int }
    public var cacheReusedTokens: Int64? { root["conversation_cache"]["reused_tokens"].int.map(Int64.init) }
    public var cachePromptTokens: Int64? { root["conversation_cache"]["prompt_tokens"].int.map(Int64.init) }
    public var cacheEvictions: Int? { root["conversation_cache"]["evictions"].int }

    // MARK: - History (60 samples, ~1 Hz)

    public var historyTPS: [Double?] { history("outputTps", "tok_s") }
    public var historyGPUUtil: [Double?] { history("gpuLoad", "gpu_util") }
    public var historyGPUTemp: [Double?] { history("gpuTempC", "gpu_temp") }
    public var historyGPUPower: [Double?] { history("powerW", "gpu_power") }
    public var historyPrefillTPS: [Double?] { history("promptTps", "prefill_tok_s_mean") }

    /// One column of the history: a list of samples (modern) or an array (legacy).
    private func history(_ modernKey: String, _ legacyKey: String) -> [Double?] {
        let samples = root["history"].array
        if !samples.isEmpty { return samples.map { $0[modernKey].double } }
        return root["history"][legacyKey].doubles
    }

    // MARK: - Requests

    public var requests: [RequestRow] { root["requests"].array.map(RequestRow.init) }
    public var requestsKept: Int? { root["requests_kept"].int }

    /// One finished generation.
    public struct RequestRow {
        public let json: JSON

        public init(json: JSON) { self.json = json }

        public var id: String { json["id"].string ?? "—" }

        /// When the request started.
        public var time: Date? {
            if let date = ISO.date(json["at"].string) { return date }
            return json["time"].double.map { Date(timeIntervalSince1970: $0) }
        }

        public var durationS: Double? {
            if let ms = json["durationMs"].double { return ms / 1000 }
            return json["duration_s"].double
        }

        public var state: String? { json["state"].string }
        public var model: String? { json["model"].string }
        public var client: String? { json["client"].string }
        public var endpoint: String? { json["endpoint"].string }

        public var promptTokens: Int? { json["tokensIn"].int ?? json["prompt_tokens"].int }
        public var reusedTokens: Int? { json["reused"].int }
        public var outputTokens: Int? { json["tokensOut"].int ?? json["output_tokens"].int }
        public var firstTokenS: Double? { json["first_engine_token_s"].double }
        public var promptMs: Double? { json["prompt_ms"].double }
        public var decodeMs: Double? { json["decode_ms"].double }

        /// Decode speed of the request.
        public var decodeTPS: Double? { json["tps"].double ?? json["decode_tok_s"].double }

        /// Prompt read speed of the request.
        public var promptTPS: Double? { json["promptTps"].double }

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
