import Foundation
import AVFoundation

@MainActor
public class ElevenLabsTTSService {
    static let shared = ElevenLabsTTSService()
    
    private let apiKey = "sk_a08ac62ab0c95ca994e786a627d0c9353a169df960d900af"
    
    private var voiceId: String {
        UserDefaults.standard.string(forKey: "selectedVoiceId") ?? "oziFLKtaxVDHQAh7o45V"
    }
    
    private let modelId = "eleven_flash_v2_5"
    private let outputFormat = "mp3_44100_192"
    
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
        currentTask?.cancel()
        
        currentTask = Task { @MainActor in
            await performSpeak(text, language: language)
        }
    }
    
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        
        if isPlaying {
            audioPlayer?.stop()
            audioPlayer = nil
            isPlaying = false
        }

        if systemSynthesizer.isSpeaking {
            systemSynthesizer.stopSpeaking(at: .immediate)
        }
        
    }
    
    func isCurrentlySpeaking() -> Bool {
        isPlaying
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

        guard networkMonitor.isReachable else {
            speakWithSystemTTS(trimmedText, language: language)
            return
        }

        if let cachedURL = audioCache.getCachedAudioURL(forText: trimmedText) {
            await playAudio(from: cachedURL)
            return
        }
        
        do {
            let audioData = try await fetchAudioFromElevenLabs(trimmedText)
            
            if let cachedURL = audioCache.cacheAudioData(audioData, forText: trimmedText) {
                await playAudio(from: cachedURL)
            } else {
                await playAudio(from: audioData)
            }
        } catch {
            speakWithSystemTTS(trimmedText, language: language)
        }
    }

    private func speakWithSystemTTS(_ text: String, language: String) {
        if isPlaying {
            audioPlayer?.stop()
            audioPlayer = nil
            isPlaying = false
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "fr-FR")
        systemSynthesizer.speak(utterance)
    }
    
    private func makeRequestBody(for text: String) -> [String: Any] {
        [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ],
            "output_format": outputFormat
        ]
    }
    
    private func fetchAudioFromElevenLabs(_ text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: makeRequestBody(for: text))
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 422,
               let errorString = String(data: data, encoding: .utf8),
               errorString.contains("quota_exceeded") || errorString.contains("credits") {
                #if os(iOS)
                NotificationCenter.default.post(name: Notification.Name("ElevenLabsQuotaExceeded"), object: nil)
                #endif
            }
            throw TTSError.apiError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    private func playAudio(from source: Any) async {
        do {
            let player: AVAudioPlayer
            if let url = source as? URL {
                player = try AVAudioPlayer(contentsOf: url)
            } else if let data = source as? Data {
                player = try AVAudioPlayer(data: data)
            } else {
                return
            }
            
            player.prepareToPlay()
            audioPlayer = player
            isPlaying = true
            player.play()
            
            while player.isPlaying && !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            
            if !Task.isCancelled {
                audioPlayer = nil
                isPlaying = false
            }
        } catch {}
    }
    
    func preloadAudio(for texts: [String]) async {
        guard memberUnlocked else { return }
        for text in texts {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }
            guard !audioCache.hasCachedAudio(forText: trimmedText) else { continue }
            guard networkMonitor.isReachable else { break }
            
            do {
                let audioData = try await fetchAudioFromElevenLabs(trimmedText)
                _ = audioCache.cacheAudioData(audioData, forText: trimmedText)
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
}

enum TTSError: Error {
    case networkError
    case apiError(statusCode: Int)
    case audioPlaybackError
    case invalidText
}

extension ElevenLabsTTSService {
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
