import SwiftUI
import StrataMonitorKit

struct MenuBarPanelView: View {
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.needsSetup {
                SetupView()
            } else if model.showSettings {
                SettingsView()
            } else if model.detailLevel == .compact {
                CompactView()
            } else {
                ExpandedView()
            }
            offlineHint
            Divider()
            footer
        }
        .frame(width: 340)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.statusSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.modelName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusBadge(text: model.statusLabel, color: statusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let gpu = model.shortGpuName { parts.append(gpu) }
        if let total = model.payload?.totalRequests { parts.append("\(Format.integer(total)) \(model.t("unit.requests"))") }
        if let uptime = model.uptimeSeconds { parts.append("\(model.t("speed.uptime")) \(Format.duration(uptime, language: model.language))") }
        if parts.isEmpty {
            if case .offline(let reason) = model.connection { return reason }
            return model.t("app.name")
        }
        return parts.joined(separator: " · ")
    }

    /// Hint shown when the server does not answer.
    @ViewBuilder
    private var offlineHint: some View {
        if case .offline = model.connection {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                Text(model.t("offline.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var statusColor: Color {
        switch model.statusTint {
        case .active: return .green
        case .busy: return .yellow
        case .idle: return .secondary
        case .offline: return .red
        }
    }

    // MARK: - Подвал

    private var footer: some View {
        HStack(spacing: 6) {
            LevelSwitch()

            Spacer(minLength: 4)

            Button {
                AppDelegate.shared?.openWebMonitor()
            } label: {
                Image(systemName: "safari")
            }
            .help(model.t("action.openBrowser"))
            .focusEffectDisabled()

            Button {
                AppDelegate.shared?.copySnapshot()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help(model.t("action.copy"))
            .focusEffectDisabled()

            Button {
                withAnimation { model.showSettings.toggle() }
            } label: {
                Image(systemName: model.showSettings ? "chevron.left" : "gearshape")
            }
            .help(model.t("action.settings"))
            .focusEffectDisabled()

            Button {
                AppDelegate.shared?.quit()
            } label: {
                Image(systemName: "power")
            }
            .help(model.t("action.quit"))
            .focusEffectDisabled()
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Detail level switch. Built from buttons, not a Picker:
/// a segmented SwiftUI Picker wrote into the model on first render
/// the last tag value (that is, "Detailed" instead of "Compact").
struct LevelSwitch: View {
    @EnvironmentObject var model: MonitorModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DetailLevel.allCases) { level in
                Button {
                    model.detailLevel = level
                } label: {
                    Text(level.title(language: model.language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(model.detailLevel == level ? Color.primary : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            model.detailLevel == level ? Color.secondary.opacity(0.22) : .clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // Рамка фокуса не нужна: панель открывается кнопкой меню-бара,
                // и рамка всегда рисовалась на первой кнопке («Компактно»).
                .focusEffectDisabled()
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

struct StatusBadge: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
