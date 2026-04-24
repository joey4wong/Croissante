import Foundation
import AVFoundation
import Combine

@MainActor
public class ElevenLabsTTSService: NSObject, ObservableObject {
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

    private struct WaveformBucket {
        var sumOfSquares: Double = 0
        var sampleCount: Int = 0
    }

    static let shared = ElevenLabsTTSService()

    private var selectedVoiceId: String {
        UserDefaults.standard.string(forKey: "selectedVoiceId") ?? TTSVoice.default.rawValue
    }

    private var voice: String {
        TTSVoice.normalizedId(selectedVoiceId)
    }

    private let requestProfileVersion = "tts-el-v4"
    private let defaultBackendBaseURL = "https://croissante-tts.joey4wong.workers.dev"

    private let networkMonitor = NetworkMonitor.shared
    private let audioCache = AudioCacheManager.shared
    private let systemSynthesizer = AVSpeechSynthesizer()

    private var audioPlayer: AVAudioPlayer?

    private var isPlaying = false
    @Published private(set) var isPlaybackActive = false
    @Published private(set) var currentPlaybackID: String?
    @Published private(set) var playbackLevel: Double = 0
    @Published private(set) var playbackProgress: Double = 0
    @Published private(set) var playbackWaveform: [Double] = []
    private var currentTask: Task<Void, Never>?
    private let waveformSampleCount = 128
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

    private override init() {
        super.init()
        setupAudioSession()
        systemSynthesizer.delegate = self
    }

    func speak(
        _ text: String,
        language: String = "fr-FR",
        contentType: ContentType = .sentence,
        cachePolicy: CachePolicy = .official,
        playbackID: String? = nil
    ) async {
        stop()

        currentTask = Task { @MainActor in
            await performSpeak(
                text,
                language: language,
                contentType: contentType,
                cachePolicy: cachePolicy,
                playbackID: playbackID
            )
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
        cachePolicy: CachePolicy,
        playbackID: String?
    ) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if systemSynthesizer.isSpeaking {
            systemSynthesizer.stopSpeaking(at: .immediate)
        }

        guard memberUnlocked else {
            speakWithSystemTTS(trimmedText, language: language, playbackID: playbackID)
            return
        }

        guard ttsEndpointURL != nil else {
            speakWithSystemTTS(trimmedText, language: language, playbackID: playbackID)
            return
        }

        guard networkMonitor.isReachable else {
            speakWithSystemTTS(trimmedText, language: language, playbackID: playbackID)
            return
        }

        let cacheText = cacheTextKey(for: trimmedText, language: language, contentType: contentType)
        if let cachedURL = audioCache.getCachedAudioURL(forText: cacheText, namespace: cachePolicy.localNamespace) {
            await playAudio(from: cachedURL, playbackID: playbackID)
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
                await playAudio(from: cachedURL, playbackID: playbackID)
            } else {
                await playAudio(from: audioData, playbackID: playbackID)
            }
        } catch {
            speakWithSystemTTS(trimmedText, language: language, playbackID: playbackID)
        }
    }

    private func speakWithSystemTTS(_ text: String, language: String, playbackID: String?) {
        stopAudioPlayback()
        beginPlayback(playbackID: playbackID, initialLevel: 0.42)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "fr-FR")
        systemSynthesizer.speak(utterance)
    }

    private func makeRequestBody(
        for text: String,
        language: String,
        contentType: ContentType,
        cachePolicy: CachePolicy
    ) -> [String: Any] {
        [
            "voice": voice,
            "input": text,
            "language": language,
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
            withJSONObject: makeRequestBody(
                for: text,
                language: language,
                contentType: contentType,
                cachePolicy: cachePolicy
            )
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

    private func playAudio(from source: Any, playbackID: String?) async {
        var preparedPlayer: AVAudioPlayer?
        do {
            let player = try makeAudioPlayer(from: source)
            preparedPlayer = player
            let waveform = makeWaveformSamples(from: source)

            player.isMeteringEnabled = true
            player.prepareToPlay()
            audioPlayer = player
            isPlaying = true
            beginPlayback(playbackID: playbackID, initialLevel: 0.18, waveform: waveform)
            guard player.play() else {
                finishAudioPlayback(for: player)
                return
            }

            while player.isPlaying {
                player.updateMeters()
                playbackLevel = normalizedPlaybackLevel(from: player.averagePower(forChannel: 0))
                playbackProgress = normalizedPlaybackProgress(for: player)
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            finishAudioPlayback(for: player)
        } catch is CancellationError {
            stopAudioPlaybackIfCurrent(preparedPlayer)
        } catch {
            stopAudioPlaybackIfCurrent(preparedPlayer)
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
        endPlayback()
    }

    private func stopAudioPlaybackIfCurrent(_ player: AVAudioPlayer?) {
        guard let player else {
            stopAudioPlayback()
            return
        }
        guard audioPlayer === player else { return }
        stopAudioPlayback()
    }

    private func finishAudioPlayback(for player: AVAudioPlayer) {
        guard audioPlayer === player else { return }
        audioPlayer = nil
        isPlaying = false
        endPlayback()
    }

    private func beginPlayback(
        playbackID: String?,
        initialLevel: Double,
        waveform: [Double] = []
    ) {
        currentPlaybackID = playbackID
        isPlaybackActive = true
        playbackLevel = initialLevel
        playbackProgress = 0
        playbackWaveform = waveform
    }

    private func endPlayback() {
        isPlaybackActive = false
        currentPlaybackID = nil
        playbackLevel = 0
        playbackProgress = 0
        playbackWaveform = []
    }

    private func normalizedPlaybackLevel(from power: Float) -> Double {
        guard power.isFinite else { return 0 }
        let clamped = max(-48, min(0, power))
        let linear = (Double(clamped) + 48) / 48
        return min(1, max(0, pow(linear, 1.35)))
    }

    private func normalizedPlaybackProgress(for player: AVAudioPlayer) -> Double {
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    private func makeWaveformSamples(from source: Any) -> [Double] {
        if let url = source as? URL {
            return waveformSamples(fromAudioURL: url, sampleCount: waveformSampleCount)
        }

        if let data = source as? Data {
            return waveformSamples(fromAudioData: data, sampleCount: waveformSampleCount)
        }

        return []
    }

    private func waveformSamples(fromAudioData data: Data, sampleCount: Int) -> [Double] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("croissante-waveform-\(UUID().uuidString)")
            .appendingPathExtension("mp3")
        do {
            try data.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return waveformSamples(fromAudioURL: tempURL, sampleCount: sampleCount)
        } catch {
            return []
        }
    }

    private func waveformSamples(fromAudioURL url: URL, sampleCount: Int) -> [Double] {
        guard sampleCount > 1 else { return [] }

        do {
            let file = try AVAudioFile(forReading: url)
            let totalFrames = Int(file.length)
            guard totalFrames > 0 else { return [] }

            var buckets = Array(repeating: WaveformBucket(), count: sampleCount)
            let frameCapacity: AVAudioFrameCount = 4096
            var processedFrames = 0

            while processedFrames < totalFrames {
                let remainingFrames = min(Int(frameCapacity), totalFrames - processedFrames)
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(remainingFrames)
                ) else {
                    break
                }

                try file.read(into: buffer, frameCount: AVAudioFrameCount(remainingFrames))
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0, let channelData = buffer.floatChannelData else { break }

                let channelCount = max(1, Int(buffer.format.channelCount))
                for frameIndex in 0..<frameLength {
                    let absoluteFrame = processedFrames + frameIndex
                    let bucketIndex = min(sampleCount - 1, absoluteFrame * sampleCount / totalFrames)
                    var framePeak: Float = 0
                    for channelIndex in 0..<channelCount {
                        framePeak = max(framePeak, abs(channelData[channelIndex][frameIndex]))
                    }
                    buckets[bucketIndex].sumOfSquares += Double(framePeak * framePeak)
                    buckets[bucketIndex].sampleCount += 1
                }

                processedFrames += frameLength
            }

            return normalizeWaveformBuckets(buckets)
        } catch {
            return []
        }
    }

    private func normalizeWaveformBuckets(_ buckets: [WaveformBucket]) -> [Double] {
        let raw = buckets.map { bucket -> Double in
            guard bucket.sampleCount > 0 else { return 0 }
            return sqrt(bucket.sumOfSquares / Double(bucket.sampleCount))
        }
        guard let peak = raw.max(), peak > 0 else { return [] }

        let normalized = raw.map { min(1, max(0, pow($0 / peak, 0.72))) }
        guard normalized.count > 2 else { return normalized }

        return normalized.indices.map { index in
            let previous = index > 0 ? normalized[index - 1] : normalized[index]
            let current = normalized[index]
            let next = index < normalized.count - 1 ? normalized[index + 1] : normalized[index]
            return previous * 0.22 + current * 0.56 + next * 0.22
        }
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
        cachePolicy: CachePolicy = .official,
        playbackID: String? = nil
    ) {
        Task {
            await shared.speak(
                text,
                language: language,
                contentType: contentType,
                cachePolicy: cachePolicy,
                playbackID: playbackID
            )
        }
    }

    @MainActor
    static func stopPlayback() {
        shared.stop()
    }
}

extension ElevenLabsTTSService: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            ElevenLabsTTSService.shared.endPlayback()
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            ElevenLabsTTSService.shared.endPlayback()
        }
    }
}
