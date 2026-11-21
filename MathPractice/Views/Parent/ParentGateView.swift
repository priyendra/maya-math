import SwiftUI

/// Simple 4-digit PIN so the student doesn't wander into answers/settings.
struct ParentGateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var unlocked = false
    @State private var error: String?
    private let existingPIN = KeychainStore.get(KeychainStore.pinAccount)

    var body: some View {
        if unlocked {
            ParentHomeView()
        } else {
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(.tint)
                    Text(existingPIN == nil ? "Choose a 4-digit parent PIN" : "Enter parent PIN").font(.title2)
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.title)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(existingPIN == nil ? "Set PIN" : "Unlock", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.count != 4 || !pin.allSatisfy(\.isNumber))
                }
                .padding()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            }
        }
    }

    private func submit() {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return }
        if let existingPIN {
            if pin == existingPIN { unlocked = true } else { error = "Wrong PIN"; pin = "" }
        } else {
            KeychainStore.set(pin, for: KeychainStore.pinAccount)
            unlocked = true
        }
    }
}

struct ParentHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = KeychainStore.apiKey ?? ""
    @State private var saved = false
    @State private var newPIN = ""

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

                Section("Chapters") {
                    ChapterReviewLinks()
                }

                Section("Parent PIN") {
                    SecureField("New 4-digit PIN", text: $newPIN).keyboardType(.numberPad)
                    Button("Change PIN") {
                        KeychainStore.set(newPIN, for: KeychainStore.pinAccount)
                        newPIN = ""
                    }
                    .disabled(newPIN.count != 4 || !newPIN.allSatisfy(\.isNumber))
                }
            }
            .navigationTitle("Parent")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: apiKey) { _, _ in saved = false }
        }
    }
}

import SwiftData

private struct ChapterReviewLinks: View {
    @Query(sort: \Chapter.createdAt, order: .reverse) private var chapters: [Chapter]

    var body: some View {
        if chapters.isEmpty {
            Text("No chapters yet").foregroundStyle(.secondary)
        }
        ForEach(chapters) { chapter in
            NavigationLink {
                ParentChapterView(chapter: chapter)
            } label: {
                let questions = chapter.questions.filter { $0.status == .needsParentReview }.count
                let gradings = chapter.allAttempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
                VStack(alignment: .leading) {
                    Text(chapter.title)
                    if questions + gradings > 0 {
                        Text("\(questions) questions and \(gradings) gradings to check").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
