import SwiftUI

/// App settings: just the Claude API key.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = KeychainStore.apiKey ?? ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(saved ? "Saved ✓" : "Save API key") {
                        KeychainStore.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: KeychainStore.apiKeyAccount)
                        saved = true
                    }
                } header: {
                    Text("Claude API key")
                } footer: {
                    Text("Stored in this iPad's Keychain. Create a key at console.anthropic.com and set a monthly spend limit on it.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: apiKey) { _, _ in saved = false }
        }
    }
}
