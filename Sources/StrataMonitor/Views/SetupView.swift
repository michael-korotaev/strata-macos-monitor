import SwiftUI
import StrataMonitorKit

/// First-run screen: asks for the address of the Strata server.
struct SetupView: View {
    @EnvironmentObject var model: MonitorModel
    @State private var address: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("setup.title"))
                .font(.system(size: 13, weight: .semibold))

            Text(model.t("setup.hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(model.t("setup.placeholder"), text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit(connect)

            HStack(spacing: 8) {
                Button(model.t("setup.connect"), action: connect)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                if model.payload != nil {
                    Button(model.t("setup.cancel")) { model.endpointText = MonitorModel.defaultEndpoint }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: 340)
        .onAppear { address = model.endpointText }
    }

    private func connect() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.endpointText = trimmed
    }
}
