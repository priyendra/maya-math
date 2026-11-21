import SwiftUI

/// App settings: the Claude API key.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var savedKey = KeychainStore.apiKey
    @State private var newKey = ""
    @State private var testState: TestState = .idle

    enum TestState: Equatable { case idle, testing, ok, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let savedKey, !savedKey.isEmpty {
                        Label("Key saved: \(Self.masked(savedKey))", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        HStack {
                            Button(testState == .testing ? "Testing…" : "Test key") { test(savedKey) }
                                .disabled(testState == .testing)
                            Spacer()
                            switch testState {
                            case .ok: Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case let .failed(message): Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing)
                            default: EmptyView()
                            }
                        }
                        Button("Remove key", role: .destructive) {
                            KeychainStore.set(nil, for: KeychainStore.apiKeyAccount)
                            self.savedKey = nil
                            testState = .idle
                        }
                    } else {
                        Label("No key saved — scanning and grading won't work until you add one.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Claude API key")
                }

                Section {
                    SecureField("Paste a key (sk-ant-…)", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(savedKey == nil ? "Save key" : "Replace key") {
                        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        KeychainStore.set(key, for: KeychainStore.apiKeyAccount)
                        savedKey = KeychainStore.apiKey
                        newKey = ""
                        test(key)
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(savedKey == nil ? "Add a key" : "Replace the key")
                } footer: {
                    Text("Stored in this iPad's Keychain. Create a key at console.anthropic.com and set a monthly spend limit on it.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// "sk-ant-api03-…AbCd": enough to recognize which key it is without showing it.
    static func masked(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return "\(key.prefix(10))…\(key.suffix(4))"
    }

    /// One tiny request to confirm the key works (costs a fraction of a cent).
    private func test(_ key: String) {
        testState = .testing
        Task {
            let client = ClaudeClient(apiKey: { key })
            do {
                _ = try await client.send(system: "Reply with the single word OK.", content: [.text("Test")],
                                          schema: nil, effort: .low, maxTokens: 200)
                testState = .ok
            } catch let ClaudeClient.ClientError.http(status, message) where status == 401 {
                testState = .failed("Key rejected (401): \(message)")
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
