import SwiftUI

/// App settings: the Claude API key.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var savedKey = KeychainStore.apiKey
    @State private var newKey = ""
    @State private var testState: TestState = .idle
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var exportError: String?

    enum TestState: Equatable { case idle, testing, ok, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let savedKey, !savedKey.isEmpty {
                        HStack(spacing: 12) {
                            Label("API key saved", systemImage: "key.fill")
                            Spacer()
                            switch testState {
                            case .testing:
                                ProgressView()
                            case .ok:
                                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                                    .accessibilityLabel("Key works")
                            case .failed:
                                Image(systemName: "xmark.octagon.fill").font(.title2).foregroundStyle(.red)
                                    .accessibilityLabel("Key failed")
                            case .idle:
                                EmptyView()
                            }
                            Button { test(savedKey) } label: {
                                Image(systemName: "checkmark.shield").font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .disabled(testState == .testing)
                            .accessibilityLabel("Check that the key works")
                        }
                        if case let .failed(message) = testState {
                            Text(message).font(.caption).foregroundStyle(.red)
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
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share data file", systemImage: "square.and.arrow.up") }
                    } else {
                        Button(exporting ? "Preparing…" : "Export app data") { export() }.disabled(exporting)
                    }
                    if let exportError { Text(exportError).foregroundStyle(.red) }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Bundles your chapters, answers and the app's Claude activity log into one file (e.g. to AirDrop to a Mac for review). It can be large.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func export() {
        exporting = true
        exportError = nil
        Task { @MainActor in
            do { exportURL = try ProblemReport.exportAllData() } catch { exportError = error.localizedDescription }
            exporting = false
        }
    }

    /// One tiny request to confirm the key works (costs a fraction of a cent).
    private func test(_ key: String) {
        testState = .testing
        Task {
            let client = ClaudeClient(apiKey: { key })
            do {
                _ = try await client.send(system: "Reply with the single word OK.", content: [.text("Test")],
                                          schema: nil, effort: .low, maxTokens: 200, kind: "key_test")
                testState = .ok
            } catch let ClaudeClient.ClientError.http(status, message) where status == 401 {
                testState = .failed("Key rejected (401): \(message)")
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
