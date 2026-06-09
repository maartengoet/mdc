import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SenderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    TextField("IP address", text: $model.settings.host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("PIN", text: $model.settings.pin)
                        .keyboardType(.asciiCapableNumberPad)

                    Stepper(value: $model.settings.displayID, in: 0...253) {
                        LabeledContent("Display ID", value: "\(model.settings.displayID)")
                    }

                    Stepper(value: $model.settings.port, in: 1...65535) {
                        LabeledContent("Port", value: "\(model.settings.port)")
                    }
                }

                Section("Network") {
                    TextField("MAC for Wake-on-LAN", text: $model.settings.mac)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    TextField("Local IP override", text: $model.settings.localIP)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Stepper(value: $model.settings.httpPort, in: 0...65535) {
                        LabeledContent(
                            "HTTP port",
                            value: model.settings.httpPort == 0 ? "Auto" : "\(model.settings.httpPort)"
                        )
                    }

                    Stepper(value: $model.settings.timeoutSeconds, in: 10...600, step: 10) {
                        LabeledContent("Timeout", value: "\(model.settings.timeoutSeconds)s")
                    }

                    Toggle("Wait for download", isOn: $model.settings.waitForDownload)
                }

                Section("Panel") {
                    Stepper(value: $model.settings.canvasWidth, in: 320...8192, step: 10) {
                        LabeledContent("Width", value: "\(model.settings.canvasWidth)")
                    }

                    Stepper(value: $model.settings.canvasHeight, in: 240...8192, step: 10) {
                        LabeledContent("Height", value: "\(model.settings.canvasHeight)")
                    }
                }

                if !model.transferLog.isEmpty {
                    Section("Transfer log") {
                        ForEach(Array(model.transferLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
