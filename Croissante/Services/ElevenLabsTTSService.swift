import Foundation
import AVFoundation

@MainActor
public class ElevenLabsTTSService {
    enum ContentType: String {
        case word
        case sentence
    }

    enum CachePolicy {
        case official
        case userOverride

        var backendValue: String {
            switch self {
            case .official: return "default"
            case .userOverride: return "bypass"
            }
        }

        var localNamespace: AudioCacheNamespace {
            switch self {
            case .official: return .official
            case .userOverride: return .userOverride
            }
        }
    }

    private static var sharedInstance: ElevenLabsTTSService?
    private static var shared: ElevenLabsTTSService {
        if let existing = sharedInstance {
            return existing
        }
        let created = ElevenLabsTTSService()
        sharedInstance = created
        return created
    }

    private var selectedVoiceId: String {
        UserDefaults.standard.string(forKey: "selectedVoiceId") ?? TTSVoice.default.rawValue
    }

    private var voice: String {
        TTSVoice.normalizedId(selectedVoiceId)
    }

    private let requestProfileVersion = "tts-el-v1"
    private let defaultBackendBaseURL = "https://croissante-tts.joey4wong.workers.dev"

    private let networkMonitor = NetworkMonitor.shared
    private let audioCache = AudioCacheManager.shared
    private let systemSynthesizer = AVSpeechSynthesizer()

    private var audioPlayer: AVAudioPlayer?

    private var isPlaying = false
    private var currentTask: Task<Void, Never>?
    private var memberUnlocked: Bool {
        UserDefaults.standard.bool(forKey: "memberUnlocked")
    }

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }()

    private var ttsEndpointURL: URL? {
        endpointURL(from: configuredBackendBaseURL)
    }

    private init() {
        setupAudioSession()
    }

    func speak(
        _ text: String,
        language: String = "fr-FR",
        contentType: ContentType = .sentence,
        cachePolicy: CachePolicy = .official
    ) async {
        stop()

        currentTask = Task { @MainActor in
            await performSpeak(text, language: language, contentType: contentType, cachePolicy: cachePolicy)
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        stopAudioPlayback()
        stopSystemSpeech()
    }

    func isCurrentlySpeaking() -> Bool {
        isPlaying || systemSynthesizer.isSpeaking
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        #endif
    }

    private func performSpeak(
        _ text: String,
        language: String,
        contentType: ContentType,
        cachePolicy: CachePolicy
    ) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if systemSynthesizer.isSpeaking {
            systemSynthesizer.stopSpeaking(at: .immediate)
        }

        guard memberUnlocked else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }

        guard ttsEndpointURL != nil else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }

        guard networkMonitor.isReachable else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }

        let cacheText = cacheTextKey(for: trimmedText, language: language, contentType: contentType)
        if let cachedURL = audioCache.getCachedAudioURL(forText: cacheText, namespace: cachePolicy.localNamespace) {
            await playAudio(from: cachedURL)
            return
        }

        do {
            let audioData = try await fetchAudioFromBackend(
                trimmedText,
                language: language,
                contentType: contentType,
                cachePolicy: cachePolicy
            )

            if let cachedURL = audioCache.cacheAudioData(
                audioData,
                forText: cacheText,
                namespace: cachePolicy.localNamespace
            ) {
                await playAudio(from: cachedURL)
            } else {
                await playAudio(from: audioData)
            }
        } catch {
            speakWithSystemTTS(trimmedText, language: language)
        }
    }

    private func speakWithSystemTTS(_ text: String, language: String) {
        stopAudioPlayback()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "fr-FR")
        systemSynthesizer.speak(utterance)
    }

    private func makeRequestBody(for text: String, contentType: ContentType, cachePolicy: CachePolicy) -> [String: Any] {
        [
            "voice": voice,
            "input": text,
            "contentType": contentType.rawValue,
            "cachePolicy": cachePolicy.backendValue
        ]
    }

    private func fetchAudioFromBackend(
        _ text: String,
        language: String,
        contentType: ContentType,
        cachePolicy: CachePolicy
    ) async throws -> Data {
        guard let url = ttsEndpointURL else { throw ElevenLabsTTSError.networkError }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: makeRequestBody(for: text, contentType: contentType, cachePolicy: cachePolicy)
        )

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsTTSError.networkError
        }

        if httpResponse.statusCode != 200 {
            throw ElevenLabsTTSError.apiError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func cacheTextKey(for text: String, language: String, contentType: ContentType) -> String {
        "\(requestProfileVersion)|\(voice)|\(language)|\(contentType.rawValue)|\(text)"
    }

    private func playAudio(from source: Any) async {
        do {
            let player = try makeAudioPlayer(from: source)

            player.prepareToPlay()
            audioPlayer = player
            isPlaying = true
            player.play()

            while player.isPlaying {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } catch is CancellationError {
            stopAudioPlayback()
        } catch {
            stopAudioPlayback()
        }
    }

    func preloadAudio(
        for texts: [String],
        language: String = "fr-FR",
        contentType: ContentType = .sentence
    ) async {
        guard memberUnlocked else { return }
        guard ttsEndpointURL != nil else { return }
        for text in texts {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }
            let cacheText = cacheTextKey(for: trimmedText, language: language, contentType: contentType)
            guard !audioCache.hasCachedAudio(forText: cacheText) else { continue }
            guard networkMonitor.isReachable else { break }

            do {
                let audioData = try await fetchAudioFromBackend(
                    trimmedText,
                    language: language,
                    contentType: contentType,
                    cachePolicy: .official
                )
                _ = audioCache.cacheAudioData(audioData, forText: cacheText)
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {}
        }
    }

    func clearCache() {
        audioCache.clearCache()
    }

    func getCacheStats() -> (size: Int64, count: Int) {
        (audioCache.getCacheSize(), audioCache.getCacheFileCount())
    }

    private func makeAudioPlayer(from source: Any) throws -> AVAudioPlayer {
        if let url = source as? URL {
            return try AVAudioPlayer(contentsOf: url)
        }
        if let data = source as? Data {
            return try AVAudioPlayer(data: data)
        }
        throw ElevenLabsTTSError.audioPlaybackError
    }

    private func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func stopSystemSpeech() {
        guard systemSynthesizer.isSpeaking else { return }
        systemSynthesizer.stopSpeaking(at: .immediate)
    }

    private var configuredBackendBaseURL: String {
        if let configured = (Bundle.main.object(forInfoDictionaryKey: "TTSBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }

        let environmentValue = ProcessInfo.processInfo.environment["TTS_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !environmentValue.isEmpty {
            return environmentValue
        }

        return defaultBackendBaseURL
    }

    private func endpointURL(from baseURLString: String) -> URL? {
        guard !baseURLString.isEmpty, let baseURL = URL(string: baseURLString) else {
            return nil
        }
        if baseURL.path.hasSuffix("/api/tts") {
            return baseURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "/api/tts" : "/\(trimmedPath)/api/tts"
        return components.url
    }
}

enum ElevenLabsTTSError: Error {
    case networkError
    case apiError(statusCode: Int)
    case audioPlaybackError
}

extension ElevenLabsTTSService {
    @MainActor
    static func speakText(
        _ text: String,
        language: String = "fr-FR",
        contentType: ContentType = .sentence,
        cachePolicy: CachePolicy = .official
    ) {
        Task {
            await shared.speak(text, language: language, contentType: contentType, cachePolicy: cachePolicy)
        }
    }

    @MainActor
    static func stopPlayback() {
        guard let sharedInstance else { return }
        sharedInstance.stop()
    }
}
