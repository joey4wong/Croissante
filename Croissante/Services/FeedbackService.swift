import Foundation

#if os(iOS)
import AVFoundation
import AudioToolbox
import UIKit
#endif

@MainActor
enum FeedbackService {
    #if os(iOS)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var queuedGearTicks = 0
    private static var gearTickTask: Task<Void, Never>?
    private static let gearTickIntervalNanoseconds: UInt64 = 18_000_000
    private static let maxQueuedGearTicks = 20
    private static var dropletPlayer = DropletSoundPlayer()
    private static var lastDropletTime: CFAbsoluteTime = 0
    private static let dropletInterval: CFTimeInterval = 0.055
    #endif

    static func prepareInteractive() {
        #if os(iOS)
        selectionGenerator.prepare()
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        rigidImpactGenerator.prepare()
        notificationGenerator.prepare()
        #endif
    }

    static func gearTick(steps: Int = 1) {
        #if os(iOS)
        let incomingSteps = max(1, steps)
        queuedGearTicks = min(maxQueuedGearTicks, queuedGearTicks + incomingSteps)

        guard gearTickTask == nil else { return }
        gearTickTask = Task { @MainActor in
            while queuedGearTicks > 0 {
                guard !Task.isCancelled else { break }
                queuedGearTicks -= 1

                rigidImpactGenerator.impactOccurred(intensity: 0.45)
                AudioServicesPlaySystemSound(1104)
                rigidImpactGenerator.prepare()

                if queuedGearTicks > 0 {
                    try? await Task.sleep(nanoseconds: gearTickIntervalNanoseconds)
                }
            }
            gearTickTask = nil
        }
        #endif
    }

    static func dropletTick(steps: Int = 1) {
        #if os(iOS)
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDropletTime >= dropletInterval else { return }
        lastDropletTime = now

        let clampedSteps = max(1, steps)
        let impactIntensity = min(0.85, 0.30 + CGFloat(clampedSteps) * 0.07)
        let soundVolume = min(0.95, 0.52 + Float(clampedSteps) * 0.08)

        lightImpactGenerator.impactOccurred(intensity: impactIntensity)
        lightImpactGenerator.prepare()
        if let dropletPlayer {
            dropletPlayer.play(volume: soundVolume)
        } else {
            AudioServicesPlaySystemSound(1104)
        }
        #endif
    }

    static func toggleChanged(isOn: Bool) {
        #if os(iOS)
        lightImpactGenerator.impactOccurred(intensity: isOn ? 0.75 : 0.55)
        lightImpactGenerator.prepare()
        #endif
    }

    static func swipeForgot() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
        #endif
    }

    static func swipeMastered() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }

    static func swipeBlurry() {
        #if os(iOS)
        mediumImpactGenerator.impactOccurred(intensity: 0.75)
        mediumImpactGenerator.prepare()
        #endif
    }

    static func swipeNoAction() {
        #if os(iOS)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }
}

#if os(iOS)
private final class DropletSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let buffer: AVAudioPCMBuffer

    init?() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return nil }
        let duration: Double = 0.11
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let sampleRate = format.sampleRate
        var phase: Double = 0
        for i in 0 ..< Int(frameCount) {
            let t = Double(i) / sampleRate
            let fastEnvelope = exp(-36 * t)
            let bodyEnvelope = exp(-13 * t)
            let sweepFrequency = 1_850 * exp(-20 * t) + 220
            phase += (2 * Double.pi * sweepFrequency) / sampleRate

            let ping = sin(phase) * fastEnvelope
            let body = sin(2 * Double.pi * 240 * t) * bodyEnvelope * 0.32
            let bubbleFrequency = 620 * exp(-8 * t)
            let bubble = sin(2 * Double.pi * bubbleFrequency * t + 1.2) * exp(-24 * t) * 0.15
            channelData[i] = Float((ping * 0.72 + body + bubble) * 0.50)
        }

        self.format = format
        self.buffer = buffer

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.85
        try? engine.start()
    }

    func play(volume: Float) {
        if !engine.isRunning {
            try? engine.start()
        }
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
}
#endif
