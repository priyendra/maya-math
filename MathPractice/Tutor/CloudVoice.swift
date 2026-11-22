import Foundation

/// OpenAI text-to-speech: a natural cloud voice for the tutor. Audio for a sentence is fetched once and cached, so
/// the next sentences can be fetched while the current one plays.
actor CloudVoice {
    static let shared = CloudVoice()

    static let engineKey = "tutorVoiceEngine"      // "apple" (default) or "openai"
    static let voiceKey = "openAIVoice"
    static let keyAccount = "openai-api-key"
    static let defaultVoice = "coral"
    /// OpenAI's voices (name, how it sounds).
    static let voices: [(String, String)] = [
        ("coral", "warm, friendly"), ("nova", "bright, energetic"), ("shimmer", "soft, gentle"),
        ("sage", "calm, clear"), ("alloy", "neutral"), ("ballad", "expressive"),
        ("ash", "relaxed, low"), ("echo", "steady, low"), ("fable", "storyteller"), ("onyx", "deep"), ("verse", "lively"),
    ]
    static let model = "gpt-4o-mini-tts"
    static let instructions = """
        You are a warm, patient math tutor talking one-on-one with a middle-school student. Speak clearly and at an \
        unhurried pace, with natural, encouraging intonation. Read math the way a teacher says it out loud.
        """

    nonisolated static var apiKey: String? { KeychainStore.get(keyAccount) }

    /// The cloud voice is chosen and has a key.
    nonisolated static var isOn: Bool {
        UserDefaults.standard.string(forKey: engineKey) == "openai" && !(apiKey ?? "").isEmpty
    }

    nonisolated static var voice: String { UserDefaults.standard.string(forKey: voiceKey) ?? defaultVoice }

    private var cache: [String: Task<Data?, Never>] = [:]
    private var order: [String] = []

    /// Starts fetching a sentence's audio (no-op if it's already fetched or on its way).
    func prefetch(_ text: String) {
        _ = task(for: text)
    }

    /// The sentence's audio (MP3), or nil if it couldn't be made (the caller falls back to the iPad's voice).
    func audio(_ text: String) async -> Data? {
        let t = task(for: text)
        let data = await t.value
        if data == nil { cache[key(text)] = nil }   // let a later try fetch it again
        return data
    }

    private func key(_ text: String) -> String { "\(Self.voice)|\(text)" }

    private func task(for text: String) -> Task<Data?, Never> {
        let k = key(text)
        if let t = cache[k] { return t }
        let voice = Self.voice
        let t = Task { await Self.fetch(text, voice: voice) }
        cache[k] = t
        order.append(k)
        if order.count > 40 { cache[order.removeFirst()] = nil }
        return t
    }

    static func fetch(_ text: String, voice: String, key: String? = nil) async -> Data? {
        guard let key = key ?? apiKey, !key.isEmpty, !text.isEmpty else { return nil }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "voice": voice, "input": text, "instructions": instructions,
                                   "response_format": "mp3"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let started = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, !data.isEmpty else {
                let message = String(data: data.prefix(300), encoding: .utf8) ?? ""
                CallLog.event("tts_failed", ["status": status, "message": message])
                return nil
            }
            CallLog.event("tts", ["chars": text.count, "ms": Int(Date().timeIntervalSince(started) * 1000), "voice": voice])
            return data
        } catch {
            CallLog.event("tts_failed", ["error": error.localizedDescription])
            return nil
        }
    }

    /// Checks a key with a tiny request. nil = works, else a short reason.
    static func test(key: String) async -> String? {
        guard let data = await fetch("Hi!", voice: voice, key: key), !data.isEmpty else {
            return "That key didn't work. Check it was copied fully and the account has credit."
        }
        return nil
    }
}
