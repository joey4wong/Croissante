import Foundation
import AVFoundation

@MainActor
public class OpenAITTSService {
    static let shared = OpenAITTSService()
    
    private var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private let supportedVoices: Set<String> = [
        "alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse"
    ]

    private var selectedVoiceId: String {
        UserDefaults.standard.string(forKey: "selectedVoiceId") ?? "coral"
    }
    
    private var voice: String {
        supportedVoices.contains(selectedVoiceId) ? selectedVoiceId : "coral"
    }
    
    private let modelId = "gpt-4o-mini-tts"
    private let outputFormat = "mp3"
    
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
    
    private init() {
        setupAudioSession()
    }
    
    func speak(_ text: String, language: String = "fr-FR") async {
        stop()
        
        currentTask = Task { @MainActor in
            await performSpeak(text, language: language)
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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        #endif
    }
    
    private func performSpeak(_ text: String, language: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if systemSynthesizer.isSpeaking {
            systemSynthesizer.stopSpeaking(at: .immediate)
        }

        guard memberUnlocked else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }
        
        guard !apiKey.isEmpty else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }

        guard networkMonitor.isReachable else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }

        let cacheText = cacheTextKey(for: trimmedText)
        if let cachedURL = audioCache.getCachedAudioURL(forText: cacheText) {
            await playAudio(from: cachedURL)
            return
        }
        
        do {
            let audioData = try await fetchAudioFromOpenAI(trimmedText)
            
            if let cachedURL = audioCache.cacheAudioData(audioData, forText: cacheText) {
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
    
    private func makeRequestBody(for text: String) -> [String: Any] {
        [
            "model": modelId,
            "voice": voice,
            "input": text,
            "response_format": outputFormat
        ]
    }
    
    private func fetchAudioFromOpenAI(_ text: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw TTSError.networkError }
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: makeRequestBody(for: text))
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            throw TTSError.apiError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }

    private func cacheTextKey(for text: String) -> String {
        "\(modelId)|\(voice)|\(text)"
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
    
    func preloadAudio(for texts: [String]) async {
        guard memberUnlocked else { return }
        guard !apiKey.isEmpty else { return }
        for text in texts {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }
            let cacheText = cacheTextKey(for: trimmedText)
            guard !audioCache.hasCachedAudio(forText: cacheText) else { continue }
            guard networkMonitor.isReachable else { break }
            
            do {
                let audioData = try await fetchAudioFromOpenAI(trimmedText)
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
        throw TTSError.audioPlaybackError
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
}

enum TTSError: Error {
    case networkError
    case apiError(statusCode: Int)
    case audioPlaybackError
}

extension OpenAITTSService {
    @MainActor
    static func speakText(_ text: String, language: String = "fr-FR") {
        Task {
            await shared.speak(text, language: language)
        }
    }
    
    @MainActor
    static func stopPlayback() {
        shared.stop()
    }
}
