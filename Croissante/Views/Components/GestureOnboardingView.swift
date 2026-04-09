import SwiftUI

struct GestureOnboardingView: View {
    let step: GestureOnboardingStep
    let onFinish: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
