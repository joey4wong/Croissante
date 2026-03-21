import Foundation

#if os(iOS)
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
