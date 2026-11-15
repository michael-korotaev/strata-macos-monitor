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
                engineCard
                cacheCard
                totalsCard
                requestsCard
                hardwareCard
            }
        }
    }

    // MARK: - Engine

    private var engineCard: some View {
        let payload = model.payload
        return SectionCard(title: model.t("section.engine")) {
            KeyValueRow(label: model.t("engine.model"), value: payload?.model ?? "—", mono: false)
            KeyValueRow(label: model.t("engine.version"), value: payload?.engineVersion ?? "—")
            KeyValueRow(label: model.t("engine.context"), value: payload?.contextTokens.map { "\(Format.integer($0))" } ?? "—")
            KeyValueRow(label: model.t("engine.kv"), value: [payload?.kvQuant, payload?.kvResident.map { "\($0)K" }]
                .compactMap { $0 }
                .joined(separator: " · "))
            KeyValueRow(label: model.t("engine.speculative"),
                        value: [
                            payload?.drafting,
                            payload?.spec.map { "spec \($0)" },
                            mtpText(payload?.mtpMax)
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · "))
            KeyValueRow(label: model.t("engine.experts"), value: payload?.expertSlots.map { "\(Format.integer($0))" } ?? "—")
            KeyValueRow(label: model.t("engine.expertCache"), value: payload?.expertCacheMiB.map { "\(Format.integer($0)) MiB" } ?? "—")
            KeyValueRow(label: model.t("engine.vramFree"), value: payload?.vramFreeMiB.map { "\(Format.integer($0)) MiB" } ?? "—")
            KeyValueRow(label: model.t("engine.arena"), value: payload?.arenaMiB.map { "\(Format.integer($0)) MiB" } ?? "—")
            KeyValueRow(label: model.t("engine.poolWorkers"), value: Format.integer(payload?.poolWorkers))
            KeyValueRow(label: model.t("engine.prefillCap"), value: Format.integer(payload?.prefillCap))
        }
    }

    private func mtpText(_ value: Int?) -> String? {
        guard let value, value > 0 else { return nil }
        return "mtp \(value)"
    }

    // MARK: - Conversation cache

    private var cacheCard: some View {
        let payload = model.payload
        return SectionCard(title: model.t("section.cache")) {
            KeyValueRow(label: model.t("cache.state"),
                        value: payload?.cacheEnabled == true ? model.t("cache.enabled") : model.t("cache.disabled"))
            KeyValueRow(label: model.t("cache.slots"), value: "\(payload?.cacheParked ?? 0) / \(payload?.cacheSlots ?? 0)")
            KeyValueRow(label: model.t("cache.reuse"), value: reusePercent.map { String(format: "%.1f%%", $0) } ?? "—")
            KeyValueRow(label: model.t("cache.requestsWithCache"), value: "\(payload?.cacheRequestsReused ?? 0) / \(payload?.cacheRequests ?? 0)")
            KeyValueRow(label: model.t("cache.tokensFromCache"), value: Format.tokens(payload?.cacheReusedTokens))
            KeyValueRow(label: model.t("cache.evictions"), value: Format.integer(payload?.cacheEvictions))
        }
    }

    private var reusePercent: Double? {
        guard let payload = model.payload, let requests = payload.cacheRequests, requests > 0 else { return nil }
        return Double(payload.cacheRequestsReused ?? 0) / Double(requests) * 100
    }

    // MARK: - Totals

    private var totalsCard: some View {
        let payload = model.payload
        return SectionCard(title: model.t("section.totals")) {
            KeyValueRow(label: model.t("totals.requests"), value: Format.integer(payload?.totalRequests))
            KeyValueRow(label: model.t("totals.promptTokens"), value: Format.tokens(payload?.totalPromptTokens))
            KeyValueRow(label: model.t("totals.fromCache"), value: Format.tokens(payload?.totalReusedTokens))
            KeyValueRow(label: model.t("totals.outputTokens"), value: Format.tokens(payload?.totalOutputTokens))
            KeyValueRow(label: model.t("totals.decodeTime"), value: Format.duration((payload?.totalDecodeMs ?? 0) / 1000, language: model.language))
            KeyValueRow(label: model.t("totals.drafts"), value: draftAcceptanceText)
            KeyValueRow(label: model.t("totals.sessionStart"), value: Format.clock(payload?.serverSince.map { Date(timeIntervalSince1970: $0) }))
        }
    }

    private var draftAcceptanceText: String {
        guard let payload = model.payload, let offered = payload.totalDraftsOffered, offered > 0,
              let accepted = payload.totalDraftsAccepted else { return "—" }
        return "\(accepted) / \(offered) (\(String(format: "%.0f%%", Double(accepted) / Double(offered) * 100)))"
    }

    // MARK: - Requests

    private var requestsCard: some View {
        let rows = Array((model.payload?.requests ?? []).prefix(8))
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
                        Text(model.t("requests.ttft"))
                        Text(model.t("requests.output"))
                        Text(model.t("requests.drafts"))
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        GridRow {
                            Text(Format.clock(row.time))
                            Text(Format.number(row.durationS, 1))
                            Text(Format.number(row.decodeTPS, 0))
                            Text(Format.number(row.firstTokenS, 2))
                            Text(Format.integer(row.outputTokens))
                            Text(row.draftAcceptance.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Hardware

    private var hardwareCard: some View {
        let payload = model.payload
        let tempHistory = (payload?.historyGPUTemp ?? []).compactMap { $0 }
        let powerHistory = (payload?.historyGPUPower ?? []).compactMap { $0 }
        return SectionCard(title: model.t("section.hardware")) {
            KeyValueRow(label: model.t("hardware.gpu"), value: payload?.gpuName ?? "—", mono: false)
            KeyValueRow(label: model.t("hardware.cpu"), value: payload?.cpuName ?? "—", mono: false)
            KeyValueRow(label: model.t("hardware.cores"),
                        value: "\(payload?.cpuCores ?? 0) / \(payload?.cpuThreads ?? 0) \(model.t("hardware.threads"))")
            KeyValueRow(label: model.t("hardware.pcie"),
                        value: "\(payload?.pcieRxMB.map { String(format: "%.0f", $0) } ?? "—") \(model.t("hardware.pcieIn")) · "
                              + "\(payload?.pcieTxMB.map { String(format: "%.0f", $0) } ?? "—") \(model.t("hardware.pcieOut"))")
            KeyValueRow(label: model.t("hardware.disk"),
                        value: "\(model.t("hardware.diskRead")) \(payload?.diskReadMB.map { String(format: "%.1f", $0) } ?? "—") MB/s · "
                              + "\(model.t("hardware.diskWrite")) \(payload?.diskWriteMB.map { String(format: "%.1f", $0) } ?? "—") MB/s")
            if !tempHistory.isEmpty {
                KeyValueRow(label: model.t("hardware.tempRange"), value: "\(Int(tempHistory.min() ?? 0)) / \(Int(tempHistory.max() ?? 0)) °C")
            }
            if !powerHistory.isEmpty {
                KeyValueRow(label: model.t("hardware.powerRange"), value: "\(Int(powerHistory.min() ?? 0)) / \(Int(powerHistory.max() ?? 0)) W")
            }
        }
    }
}
