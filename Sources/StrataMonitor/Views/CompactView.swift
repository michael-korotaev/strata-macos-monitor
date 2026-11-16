import SwiftUI
import StrataMonitorKit

struct StatTile: View {
    var label: String
    var value: String
    var meter: Double? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let meter {
                MeterBar(value: meter, tint: tint)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactView: View {
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            speedRow
            Divider()
            chips
            if model.isGenerating { liveRow }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Скорость

    private var speedRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.headlineTPS.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(model.headlineIsPrefill ? model.t("unit.prefillTps") : model.t("unit.tps"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Sparkline(values: model.payload?.historyTPS ?? [],
                      color: model.isGenerating ? .green : .secondary)
                .frame(width: 116, height: 32)
        }
    }

    private var subtitle: String {
        guard case .online = model.connection else {
            if case .offline(let reason) = model.connection { return reason }
            return model.t("speed.connecting")
        }
        var parts: [String] = []
        if let mean = model.meanTPS { parts.append("\(model.t("speed.mean")) \(String(format: "%.0f", mean))") }
        if model.isGenerating {
            parts.append(model.t("speed.window"))
        } else if let uptime = model.uptimeSeconds {
            parts.append("\(model.t("speed.uptime")) \(Format.duration(uptime, language: model.language))")
        }
        return parts.isEmpty ? model.statusLabel : parts.joined(separator: " · ")
    }

    // MARK: - Железо

    private var chips: some View {
        let payload = model.payload
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                StatTile(label: model.t("label.gpu"),
                         value: Format.percent(payload?.gpuUtil),
                         meter: payload?.gpuUtil,
                         tint: .green)
                StatTile(label: model.t("label.vram"),
                         value: vramText,
                         meter: vramPercent,
                         tint: .blue)
                StatTile(label: model.t("label.temp"),
                         value: payload?.gpuTemp.map { String(format: "%.0f°C", $0) } ?? "—",
                         meter: payload?.gpuTemp.map { $0 * 100 / 95 },
                         tint: .orange)
            }
            GridRow {
                StatTile(label: model.t("label.power"),
                         value: payload?.gpuPower.map { String(format: "%.0f W", $0) } ?? "—",
                         meter: powerPercent,
                         tint: .purple)
                StatTile(label: model.t("label.cpu"),
                         value: Format.percent(payload?.cpuUsage),
                         meter: payload?.cpuUsage,
                         tint: .teal)
                StatTile(label: model.t("label.ram"),
                         value: ramText,
                         meter: ramPercent,
                         tint: .pink)
            }
        }
    }

    private var vramText: String {
        guard let payload = model.payload else { return "—" }
        return "\(Format.gib(payload.gpuMemUsed)) / \(Format.gib(payload.gpuMemTotal)) GiB"
    }

    private var vramPercent: Double? {
        guard let payload = model.payload, let total = payload.gpuMemTotal, total > 0,
              let used = payload.gpuMemUsed else { return nil }
        return Double(used) / Double(total) * 100
    }

    private var ramText: String {
        guard let payload = model.payload else { return "—" }
        return "\(Format.gib(payload.ramUsed)) / \(Format.gib(payload.ramTotal)) GiB"
    }

    private var ramPercent: Double? {
        guard let payload = model.payload, let total = payload.ramTotal, total > 0,
              let used = payload.ramUsed else { return nil }
        return Double(used) / Double(total) * 100
    }

    private var powerPercent: Double? {
        guard let payload = model.payload, let limit = payload.gpuPowerLimit, limit > 0,
              let power = payload.gpuPower else { return nil }
        return power / limit * 100
    }

    // MARK: - Текущий запрос

    private var liveRow: some View {
        let payload = model.payload
        let generated = Double(payload?.liveGenerated ?? 0)
        let maxTokens = Double(payload?.liveMaxTokens ?? 0)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(model.phaseLabel ?? model.t("speed.generating"))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(payload?.liveGenerated ?? 0) / \(payload?.liveMaxTokens ?? 0) \(model.t("unit.tokens"))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MeterBar(value: maxTokens > 0 ? generated / maxTokens * 100 : nil, tint: .green)
            HStack(spacing: 8) {
                Text("\(model.t("live.elapsed")) \(Format.seconds(payload?.liveElapsed, language: model.language))")
                if let prefill = payload?.prefillTPSMean, prefill > 0 {
                    Text("\(model.t("live.prefill")) \(String(format: "%.0f", prefill)) \(model.t("unit.tps"))")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }
}
