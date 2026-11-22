import AVFoundation
import Speech

/// The tutor's voice: the best installed English female voice (a downloaded Premium/Enhanced voice if there is one).
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    /// Bumped by stop(), so a sentence whose cloud audio arrives after she interrupted isn't played.
    private var generation = 0
    private var finished: CheckedContinuation<Void, Never>?
    /// Debug/UI tests: don't make sound, just wait a moment per line.
    var silent = false

    static let voiceKey = "tutorVoiceID"

    /// Installed English voices, best first (premium > enhanced > standard; female and US English preferred).
    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { score($0) > score($1) }
    }

    private static func score(_ v: AVSpeechSynthesisVoice) -> Int {
        var s = v.quality.rawValue * 100
        if v.gender == .female { s += 40 }
        if v.language == "en-US" { s += 20 }
        if ["Ava", "Zoe", "Samantha", "Allison", "Susan"].contains(where: v.name.hasPrefix) { s += 5 }
        return s
    }

    /// The voice chosen in Settings, else the best installed female English voice.
    static var voice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: voiceKey), let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return englishVoices.first { $0.gender == .female } ?? englishVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static func describe(_ v: AVSpeechSynthesisVoice?) -> String {
        guard let v else { return "none" }
        let q = v.quality == .premium ? "Premium" : v.quality == .enhanced ? "Enhanced" : "Standard"
        return "\(v.name) (\(q), \(v.language))"
    }

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Starts fetching a coming sentence's cloud audio, so it plays without a pause.
    func prefetch(_ text: String) {
        guard !silent, CloudVoice.isOn else { return }
        Task { await CloudVoice.shared.prefetch(text) }
    }

    /// Speaks one line and returns when it has finished (or was stopped). Uses the cloud voice when it's on,
    /// and the iPad's voice if the cloud audio can't be had.
    func speak(_ text: String) async {
        stop()
        if silent {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return
        }
        if CloudVoice.isOn {
            let gen = generation
            let data = await CloudVoice.shared.audio(text)
            guard gen == generation, !Task.isCancelled else { return }
            if let data, let p = try? AVAudioPlayer(data: data) {
                player = p
                p.delegate = self
                p.prepareToPlay()
                await withCheckedContinuation { c in
                    finished = c
                    if !p.play() { resume() }
                }
                return
            }
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.98
        u.postUtteranceDelay = 0.08
        await withCheckedContinuation { c in
            finished = c
            synth.speak(u)
        }
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.resume() }
    }

    private func resume() {
        finished?.resume()
        finished = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}

/// Hands-free listening: on-device speech recognition; her turn ends after a short silence (pencil activity
/// counts as "still going", so she can circle something while she talks).
@MainActor
final class Listener {
    var onHeard: (String) -> Void = { _ in }
    var onFinished: (String) -> Void = { _ in }
    var onGaveUp: () -> Void = {}

    static let endOfTurnSilence: TimeInterval = 1.5
    static let giveUpAfter: TimeInterval = 45

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var transcript = ""
    private var startedAt = Date()
    private var lastActivity = Date()
    private(set) var isListening = false

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    func start() throws {
        stop()
        guard let recognizer, recognizer.isAvailable else { throw ListenError.unavailable }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenError.noMicrophone }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = ["square root", "squared", "cubed", "factor", "exponent", "variable",
                                     "coefficient", "parentheses", "binomial", "trinomial", "polynomial"]
        self.request = request
        transcript = ""
        startedAt = Date()
        lastActivity = Date()

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        try engine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            DispatchQueue.main.async {
                guard let self, self.isListening else { return }
                if let text, text != self.transcript {
                    self.transcript = text
                    self.lastActivity = Date()
                    self.onHeard(text)
                }
                if error != nil, self.transcript.isEmpty { self.restartAfterError() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// She's writing: keep her turn open.
    func noteActivity() { lastActivity = Date() }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isListening || task != nil else { return }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func tick() {
        guard isListening else { return }
        let now = Date()
        let said = transcript.trimmingCharacters(in: .whitespaces)
        if !said.isEmpty, now.timeIntervalSince(lastActivity) >= Self.endOfTurnSilence {
            stop()
            onFinished(said)
        } else if said.isEmpty, now.timeIntervalSince(startedAt) >= Self.giveUpAfter, now.timeIntervalSince(lastActivity) >= Self.giveUpAfter {
            stop()
            onGaveUp()
        }
    }

    /// Recognition can end on its own after a long quiet stretch; keep listening.
    private var lastRestart = Date.distantPast
    private func restartAfterError() {
        let started = startedAt
        stop()
        guard Date().timeIntervalSince(lastRestart) > 2 else { onGaveUp(); return }
        lastRestart = Date()
        do {
            try start()
            startedAt = started
        } catch {
            onGaveUp()
        }
    }

    enum ListenError: LocalizedError {
        case unavailable, noMicrophone
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Speech recognition isn't available right now."
            case .noMicrophone: return "No microphone is available."
            }
        }
    }
}
