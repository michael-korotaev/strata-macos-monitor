import SwiftUI
import StrataMonitorKit

struct SectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct KeyValueRow: View {
    var label: String
    var value: String
    var mono: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
                .lineLimit(1)
        }
    }
}

struct ExpandedView: View {
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CompactView()
                card(model.t("section.engine"), title: model.t("section.engine"), rows: engineRows)
                card(model.t("section.cache"), title: model.t("section.cache"), rows: cacheRows)
                card(model.t("section.totals"), title: model.t("section.totals"), rows: totalsRows)
                requestsCard
                card(model.t("section.hardware"), title: model.t("section.hardware"), rows: hardwareRows)
            }
        }
    }

    // MARK: - Cards

    /// Карточка прячется целиком, если для неё нет ни одной строки.
    @ViewBuilder
    private func card(_ key: String, title: String, rows: [(String, String)]) -> some View {
        if !rows.isEmpty {
            SectionCard(title: title) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    KeyValueRow(label: row.0, value: row.1)
                }
            }
        }
    }

    // MARK: - Engine

    private var engineRows: [(String, String)] {
        let payload = model.payload
        let info = model.staticInfo
        var rows: [(String, String)] = []

        if !model.modelName.isEmpty, model.modelName != "—" {
            rows.append((model.t("engine.model"), model.modelName))
        }
        if let version = payload?.engineVersion {
            rows.append((model.t("engine.version"), version))
        }
        if let backend = info?.backend {
            rows.append((model.t("engine.backend"), backend.uppercased()))
        }
        if let quant = info?.modelQuant {
            rows.append((model.t("engine.quant"), quant))
        }
        if let context = payload?.contextTokens {
            var text = Format.integer(context)
            if let used = payload?.contextUsedTokens, used > 0 {
                text += " · \(Format.tokens(Int64(used))) \(model.t("unit.tokens"))"
            }
            rows.append((model.t("engine.context"), text))
        }
        if let kv = info?.modelKVModes, !kv.isEmpty {
            var text = kv.joined(separator: " / ")
            if let perToken = info?.modelKVPerTokenKb {
                text += " · \(String(format: "%.0f", perToken)) KB/\(model.t("unit.tokens"))"
            }
            rows.append((model.t("engine.kv"), text))
        }
        let experts = info?.modelExperts ?? payload?.expertSlots
        if let experts, experts > 0 {
            var text = Format.integer(experts)
            if let used = payload?.expertCacheUsed, used > 0 {
                text += " · \(used) \(model.t("engine.expertCache"))"
            }
            rows.append((model.t("engine.experts"), text))
        }
        if let layers = info?.modelLayers, layers > 0 {
            rows.append((model.t("engine.layers"), Format.integer(layers)))
        }
        if let host = info?.hostName {
            let platform = info?.hostPlatform ?? ""
            rows.append((model.t("engine.host"), platform.isEmpty ? host : "\(host) · \(platform)"))
        }
        return rows
    }

    // MARK: - Conversation cache

    private var cacheRows: [(String, String)] {
        let payload = model.payload
        var rows: [(String, String)] = []

        if let source = payload?.cacheSource {
            guard source != "unavailable" else { return rows }
            rows.append((model.t("cache.state"), source))
        } else if let enabled = payload?.cacheEnabled {
            rows.append((model.t("cache.state"),
                         enabled ? model.t("cache.enabled") : model.t("cache.disabled")))
        }
        if let slots = payload?.cacheSlots {
            var text = "\(payload?.cacheParked ?? 0) / \(slots)"
            if let miB = payload?.conversationCacheMiB {
                text += " · \(Format.integer(miB)) MiB"
            }
            rows.append((model.t("cache.slots"), text))
        }
        if let percent = reusePercent {
            rows.append((model.t("cache.reuse"), String(format: "%.1f%%", percent)))
        }
        if let requests = payload?.cacheRequests {
            rows.append((model.t("cache.requestsWithCache"),
                         "\(payload?.cacheRequestsReused ?? 0) / \(requests)"))
        }
        if let tokens = payload?.cacheReusedTokens {
            rows.append((model.t("cache.tokensFromCache"), Format.tokens(tokens)))
        }
        if let evictions = payload?.cacheEvictions {
            rows.append((model.t("cache.evictions"), Format.integer(evictions)))
        }
        return rows
    }

    private var reusePercent: Double? {
        guard let payload = model.payload, let requests = payload.cacheRequests, requests > 0 else { return nil }
        return Double(payload.cacheRequestsReused ?? 0) / Double(requests) * 100
    }

    // MARK: - Totals

    private var totalsRows: [(String, String)] {
        let payload = model.payload
        var rows: [(String, String)] = []

        if let requests = payload?.totalRequests {
            rows.append((model.t("totals.requests"), Format.integer(requests)))
        }
        if let tokens = payload?.totalPromptTokens {
            rows.append((model.t("totals.promptTokens"), Format.tokens(tokens)))
        }
        if let tokens = payload?.totalOutputTokens {
            rows.append((model.t("totals.outputTokens"), Format.tokens(tokens)))
        }
        if let tokens = payload?.totalReusedTokens, tokens > 0 {
            rows.append((model.t("totals.fromCache"), Format.tokens(tokens)))
        }
        if let tps = payload?.totalAvgTPS, tps > 0 {
            rows.append((model.t("totals.avgTps"), String(format: "%.1f %@", tps, model.t("unit.tps"))))
        }
        if let ttft = payload?.totalTTFTMs, ttft > 0 {
            rows.append((model.t("totals.ttft"), String(format: "%.0f ms", ttft)))
        }
        if let ms = payload?.totalDecodeMs {
            rows.append((model.t("totals.decodeTime"),
                         Format.duration(ms / 1000, language: model.language)))
        }
        if let offered = payload?.totalDraftsOffered, offered > 0 {
            let accepted = payload?.totalDraftsAccepted ?? 0
            rows.append((model.t("totals.drafts"),
                         "\(accepted) / \(offered) (\(String(format: "%.0f%%", Double(accepted) / Double(offered) * 100)))"))
        }
        if let since = payload?.serverSince {
            rows.append((model.t("totals.sessionStart"), Format.clock(since)))
        }
        return rows
    }

    // MARK: - Requests

    private var requestsCard: some View {
        let rows = Array((model.payload?.requests ?? []).prefix(8))
        let showTTFT = rows.contains { $0.firstTokenS != nil }
        let showDrafts = rows.contains { $0.draftAcceptance != nil }
        return SectionCard(title: model.t("section.requests")) {
            if rows.isEmpty {
                Text(model.t("requests.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
                    GridRow {
                        Text(model.t("requests.time")).gridColumnAlignment(.leading)
                        Text(model.t("requests.seconds"))
                        Text(model.t("requests.tps"))
                        if showTTFT { Text(model.t("requests.ttft")) }
                        Text(model.t("requests.output"))
                        if showDrafts { Text(model.t("requests.drafts")) }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        GridRow {
                            Text(Format.clock(row.time))
                            Text(Format.number(row.durationS, 1))
                            Text(Format.number(row.decodeTPS, 0))
                            if showTTFT { Text(Format.number(row.firstTokenS, 2)) }
                            Text(Format.integer(row.outputTokens))
                            if showDrafts {
                                Text(row.draftAcceptance.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Hardware

    private var hardwareRows: [(String, String)] {
        let payload = model.payload
        let info = model.staticInfo
        var rows: [(String, String)] = []

        if let gpu = info?.gpuName ?? payload?.gpuName {
            rows.append((model.t("hardware.gpu"), gpu))
        }
        if let cpu = info?.cpuName ?? payload?.cpuName {
            rows.append((model.t("hardware.cpu"), cpu))
        }
        let cores = info?.cpuCores ?? payload?.cpuCores
        let threads = info?.cpuThreads ?? payload?.cpuThreads
        if let cores, cores > 0 {
            let text = threads.map { "\(cores) / \($0) \(model.t("hardware.threads"))" } ?? "\(cores)"
            rows.append((model.t("hardware.cores"), text))
        }
        if let rx = payload?.pcieRxMB {
            var text = String(format: "%.0f", rx) + " " + model.t("hardware.pcieIn")
            if let tx = payload?.pcieTxMB {
                text += " · " + String(format: "%.0f", tx) + " " + model.t("hardware.pcieOut")
            }
            rows.append((model.t("hardware.pcie"), text))
        }
        if let read = payload?.diskReadMB {
            var text = "\(model.t("hardware.diskRead")) \(String(format: "%.2f", read)) MB/s"
            if let write = payload?.diskWriteMB {
                text += " · \(model.t("hardware.diskWrite")) \(String(format: "%.2f", write)) MB/s"
            }
            rows.append((model.t("hardware.disk"), text))
        }
        if let free = info?.diskFreeGb {
            rows.append((model.t("hardware.diskFree"), String(format: "%.0f GB", free)))
        }
        let temps = (payload?.historyGPUTemp ?? []).compactMap { $0 }
        if !temps.isEmpty {
            rows.append((model.t("hardware.tempRange"),
                         "\(Int(temps.min() ?? 0)) / \(Int(temps.max() ?? 0)) °C"))
        }
        let powers = (payload?.historyGPUPower ?? []).compactMap { $0 }
        if !powers.isEmpty {
            rows.append((model.t("hardware.powerRange"),
                         "\(Int(powers.min() ?? 0)) / \(Int(powers.max() ?? 0)) W"))
        }
        return rows
    }
}
