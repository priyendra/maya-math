import AVFoundation
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
                TutorVoiceSection()
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

/// Pick the tutor's voice by ear. Better voices are free downloads in iPadOS Settings.
struct TutorVoiceSection: View {
    @AppStorage(Speaker.voiceKey) private var chosen = ""
    @AppStorage(CloudVoice.engineKey) private var engine = "apple"
    @AppStorage(CloudVoice.voiceKey) private var cloudVoice = CloudVoice.defaultVoice
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var synth = AVSpeechSynthesizer()
    @State private var player: AVAudioPlayer?
    @State private var hasKey = !(CloudVoice.apiKey ?? "").isEmpty
    @State private var newKey = ""
    @State private var checking = false
    @State private var keyError: String?
    @State private var previewing = false

    private let sample = "Hi! Let's look at where it went wrong. The square root of nine a squared is three a."

    var body: some View {
        Section {
            Picker("Voice from", selection: $engine) {
                Text("This iPad").tag("apple")
                Text("OpenAI (online)").tag("openai")
            }
            .pickerStyle(.segmented)
            if engine == "openai" {
                if hasKey {
                    Picker("Voice", selection: $cloudVoice) {
                        ForEach(CloudVoice.voices, id: \.0) { v in Text("\(v.0.capitalized) — \(v.1)").tag(v.0) }
                    }
                    HStack {
                        Label("OpenAI key saved", systemImage: "key.fill")
                        Spacer()
                        Button("Remove", role: .destructive) { KeychainStore.set(nil, for: CloudVoice.keyAccount); hasKey = false }
                    }
                } else {
                    SecureField("Paste your OpenAI API key (sk-…)", text: $newKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        saveKey()
                    } label: {
                        if checking { ProgressView() } else { Text("Save key") }
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                    if let keyError { Text(keyError).foregroundStyle(.red).font(.callout) }
                }
            } else {
                Picker("Voice", selection: $chosen) {
                    Text("Automatic (best installed)").tag("")
                    ForEach(voices, id: \.identifier) { v in Text(Speaker.describe(v)).tag(v.identifier) }
                }
            }
            Button { preview() } label: {
                HStack { Label("Preview", systemImage: "play.circle"); if previewing { ProgressView().padding(.leading, 6) } }
            }
            .disabled(engine == "openai" && !hasKey)
        } header: {
            Text("Tutor voice")
        } footer: {
            if engine == "openai" {
                Text("A natural voice from OpenAI. Each sentence the tutor says is sent to OpenAI to be spoken (a cent or two per minute of speech). If it can't be reached, the iPad's voice is used. The key is stored in this iPad's Keychain.")
            } else {
                Text("Now using: \(Speaker.describe(Speaker.voice)). For a natural voice, download one for free: iPad Settings → Accessibility → Spoken Content → Voices → English → pick a voice marked Premium or Enhanced (e.g. Ava, Zoe), then come back and choose it here.")
            }
        }
        .onAppear { voices = Speaker.englishVoices }
    }

    private func saveKey() {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        keyError = nil
        Task {
            if let problem = await CloudVoice.test(key: key) {
                keyError = problem
            } else {
                KeychainStore.set(key, for: CloudVoice.keyAccount)
                hasKey = true
                newKey = ""
            }
            checking = false
        }
    }

    private func preview() {
        synth.stopSpeaking(at: .immediate)
        player?.stop()
        if engine == "openai" {
            previewing = true
            Task {
                let data = await CloudVoice.fetch(sample, voice: cloudVoice)
                previewing = false
                if let data, let p = try? AVAudioPlayer(data: data) { player = p; p.play() }
                else { keyError = "Couldn't get the voice from OpenAI just now." }
            }
            return
        }
        let u = AVSpeechUtterance(string: sample)
        u.voice = Speaker.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.98
        synth.speak(u)
    }
}
