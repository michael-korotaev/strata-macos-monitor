import SwiftUI
import StrataMonitorKit

struct SettingsView: View {
    @EnvironmentObject var model: MonitorModel

    @State private var endpointDraft: String = ""
    @State private var launchAtLogin = false
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("settings.title"))
                .font(.system(size: 12, weight: .semibold))

            field(model.t("settings.endpoint")) {
                TextField(model.t("settings.endpointPlaceholder"), text: $endpointDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit(applyEndpoint)
                HStack(spacing: 6) {
                    Button(model.t("settings.apply"), action: applyEndpoint)
                        .controlSize(.small)
                    if model.connection.isOnline {
                        Button(model.t("settings.openBrowser")) {
                            AppDelegate.shared?.openWebMonitor()
                        }
                        .controlSize(.small)
                    }
                }
            }

            field(model.t("settings.flavor")) {
                Menu {
                    ForEach(StrataFlavor.allCases) { flavor in
                        Button {
                            model.serverFlavor = flavor
                        } label: {
                            Text(flavor.title(language: model.language))
                        }
                    }
                } label: {
                    Text(model.serverFlavor.title(language: model.language))
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }

            field(model.t("settings.interval")) {
                Menu {
                    ForEach(Self.intervals, id: \.self) { value in
                        Button {
                            model.pollInterval = value
                        } label: {
                            Text(Self.intervalLabel(value))
                        }
                    }
                } label: {
                    Text(Self.intervalLabel(model.pollInterval))
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }

            field(model.t("settings.menubar")) {
                Menu {
                    ForEach(MenubarFormat.allCases) { format in
                        Button {
                            model.menubarFormat = format
                        } label: {
                            Text(format.title(language: model.language))
                        }
                    }
                } label: {
                    Text(model.menubarFormat.title(language: model.language))
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }

            field(model.t("settings.language")) {
                Menu {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            model.language = language
                        } label: {
                            Text(language.title)
                        }
                    }
                } label: {
                    Text(model.language.title)
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }

            field(model.t("settings.launchAtLogin")) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunch(newValue)
                    }
                if let launchError {
                    Text("\(model.t("settings.launchFailed")): \(launchError)")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }

            Divider()

            HStack {
                Text(model.t("settings.updated"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.lastSuccess.map { Format.clock($0) } ?? "—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340)
        .onAppear {
            endpointDraft = model.endpointText
            launchAtLogin = AppDelegate.shared?.launchAtLoginEnabled ?? false
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func applyEndpoint() {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.endpointText = trimmed
    }

    private func toggleLaunch(_ enabled: Bool) {
        do {
            try AppDelegate.shared?.setLaunchAtLogin(enabled)
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = AppDelegate.shared?.launchAtLoginEnabled ?? false
        }
    }

    static let intervals: [Double] = [0.5, 1, 2, 5]

    static func intervalLabel(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value)) s" : "\(value) s"
    }
}
