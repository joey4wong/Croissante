import SwiftUI

struct GalaxySlot: Identifiable {
    let id: String
    let word: SimpleWord?

    var isBlank: Bool { word == nil }
}

struct WordGalaxyView: View {
    let slots: [GalaxySlot]
    let flyInWordId: String?
    let returnToken: Int
    let isInteractive: Bool
    let onSelectCard: (GalaxySelectedCardTransitionRequest) -> Void
    let onAddTapped: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealProgress: CGFloat = 0
    @State private var animationStart = Date()
    @State private var canSelect = false
    @State private var orbitDragOffset = 0.0
    @State private var previousDragTranslationX: CGFloat = 0
    @State private var touchDownDate: Date? = nil
    @State private var selectedCardIndex: Int? = nil
    @State private var selectionAnimationStartTime: Date? = nil
    @State private var returnAnimationStartTime: Date? = nil
    @State private var spinDragDelta: Double = 0
    @State private var isDealing = true
    @State private var flyInStartTime: Date? = nil
    @State private var activeFlyInWordId: String? = nil

    private let orbitSpeed: Double = 36
    private let pileAngle: Double = .pi * 0.65
    private let dealDuration: Double = 0.56
    private let dealTapUnlockDelay: Double = 0.36
    private let dealStaggerPerCard: Double = 0.012
    private let compressedFanOrbitSteps: Double = 3.0
    private let compressedFanPower: Double = 0.82
    private let depthZSwitchProgress: Double = 0.42
    private let frontFacingAngle: Double = -.pi / 2.0
    private let selectionTransitionDuration: Double = 0.48
    private let returnTransitionDuration: Double = 0.36
    private let flyInDuration: Double = 0.72

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { context in
                    galaxyFrame(context: context, geo: geo)
                }
                .contentShape(Rectangle())
                .gesture(orbitGesture(in: geo))
            }
            .onAppear(perform: startDeal)
            .onChange(of: returnToken) { _, _ in
                returnToOrbit()
            }
            .onChange(of: flyInWordId) { _, newValue in
                guard let newValue else { return }
                activeFlyInWordId = newValue
                flyInStartTime = Date()
            }
        }
    }

    private var addButtonOpacity: Double {
        selectedCardIndex == nil ? 1 : 0
    }

    private func startDeal() {
        animationStart = Date()
        canSelect = false
        selectedCardIndex = nil
        selectionAnimationStartTime = nil
        spinDragDelta = 0
        isDealing = true
        withAnimation(.linear(duration: dealDuration)) {
            revealProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dealDuration) {
            isDealing = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dealTapUnlockDelay) {
            canSelect = true
        }
    }

    private func orbitGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isInteractive, selectedCardIndex == nil, selectionAnimationStartTime == nil, !isDealing else { return }
                if touchDownDate == nil {
                    touchDownDate = Date()
                }
                let delta = value.translation.width - previousDragTranslationX
                previousDragTranslationX = value.translation.width
                orbitDragOffset += Double(delta) / 80.0
                FeedbackService.wheelSpinTick(deltaX: delta)
            }
            .onEnded { value in
                guard isInteractive, !isDealing else {
                    previousDragTranslationX = 0
                    return
                }
                FeedbackService.wheelSpinEnded()
                let totalDrag = abs(value.translation.width) + abs(value.translation.height)
                let projectedDeltaX = value.predictedEndTranslation.width - value.translation.width
                let projectedDeltaY = value.predictedEndTranslation.height - value.translation.height
                let projectedDrag = abs(projectedDeltaX) + abs(projectedDeltaY)
                let isTap = totalDrag < 10 && projectedDrag < 12 && canSelect
                if isTap {
                    let elapsed = (touchDownDate ?? Date()).timeIntervalSince(animationStart)
                    let cards = projectedCards(elapsed: elapsed)
                    if let hitCard = hitTestCard(at: value.location, in: geo.size, cards: cards) {
                        selectCard(hitCard)
                    }
                } else if selectedCardIndex == nil {
                    applyInertia(using: value)
                }
                previousDragTranslationX = 0
                if selectedCardIndex == nil, let td = touchDownDate {
                    let pauseDuration = Date().timeIntervalSince(td)
                    animationStart = animationStart.addingTimeInterval(pauseDuration)
                    touchDownDate = nil
                }
            }
    }

    @ViewBuilder
    private func galaxyFrame(context: TimelineViewDefaultContext, geo: GeometryProxy) -> some View {
        let referenceDate = touchDownDate ?? context.date
        let elapsed = referenceDate.timeIntervalSince(animationStart)
        let spinT: Double = {
            guard let selectionAnimationStartTime else { return 0 }
            return min(1.0, context.date.timeIntervalSince(selectionAnimationStartTime) / selectionTransitionDuration)
        }()
        let spinExtra = spinDragDelta * galaxySmoothStep(spinT)
        let selectionProgress = spinT
        let returnProgress: Double = {
            guard let returnAnimationStartTime else { return 1 }
            return min(1.0, context.date.timeIntervalSince(returnAnimationStartTime) / returnTransitionDuration)
        }()
        let cards = projectedCards(elapsed: elapsed, extraDragOffset: spinExtra)
        let visibleCards = cards.filter { $0.cardIndex != selectedCardIndex }
        let hideForSelection = selectedCardIndex != nil ? galaxySmoothStep(selectionProgress) : 0
        let galaxyOpacity = max(0.0, 1.0 - hideForSelection) * galaxySmoothStep(returnProgress)
        let flyInProgress: Double = {
            guard let flyInStartTime else { return 1 }
            return min(1.0, context.date.timeIntervalSince(flyInStartTime) / flyInDuration)
        }()

        ZStack {
            GalaxyAddButton(action: {
                guard isInteractive, selectedCardIndex == nil else { return }
                onAddTapped()
            })
            .opacity(addButtonOpacity)
            .allowsHitTesting(isInteractive && selectedCardIndex == nil)
            .offset(y: -29)
            .zIndex(0)

            if galaxyOpacity > 0.001 {
                ForEach(visibleCards) { card in
                    renderedGalaxyCard(card, flyInProgress: flyInProgress)
                        .opacity(galaxyOpacity)
                }
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private func renderedGalaxyCard(_ card: ProjectedGalaxyCard, flyInProgress: Double) -> some View {
        var state = orbitGalaxyCardState(for: card)
        var zOrder = card.zOrder
        if let activeFlyInWordId, card.slot.word?.id == activeFlyInWordId, flyInProgress < 1 {
            let t = galaxySmoothStep(flyInProgress)
            state = SelectedGalaxyCardState(
                offset: CGSize(width: state.offset.width * t, height: state.offset.height * t),
                scale: galaxyLerp(0.18, state.scale, t),
                tiltY: state.tiltY * t,
                tiltZ: galaxyLerp(0, state.tiltZ, t),
                opacity: galaxyLerp(0.0, state.opacity, min(1, flyInProgress * 2.2)),
                blur: 0
            )
            zOrder = 1000
        }
        return Group {
            if let word = card.slot.word {
                GalaxyWordCard(word: word, materialEnabled: selectionAnimationStartTime == nil)
            } else {
                GalaxyBlankCard()
            }
        }
        .rotation3DEffect(.degrees(state.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0)
        .rotationEffect(.degrees(state.tiltZ))
        .scaleEffect(state.scale)
        .offset(state.offset)
        .opacity(state.opacity)
        .blur(radius: state.blur)
        .zIndex(zOrder)
    }

    private func selectCard(_ hitCard: ProjectedGalaxyCard) {
        guard let word = hitCard.slot.word, isInteractive, selectedCardIndex == nil, selectionAnimationStartTime == nil else { return }
        selectedCardIndex = hitCard.cardIndex
        canSelect = false

        var deltaAngle = frontFacingAngle - hitCard.angle
        deltaAngle = deltaAngle.truncatingRemainder(dividingBy: 2.0 * .pi)
        if deltaAngle > .pi { deltaAngle -= 2.0 * .pi }
        if deltaAngle < -.pi { deltaAngle += 2.0 * .pi }
        spinDragDelta = deltaAngle * 180.0 / (orbitSpeed * .pi)
        selectionAnimationStartTime = Date()
        FeedbackService.cardMetaButtonTap()
        onSelectCard(
            GalaxySelectedCardTransitionRequest(
                word: word,
                sourceCardWidth: 66,
                galaxyScale: 1,
                rollStartAngle: hitCard.angle,
                rollEndAngle: hitCard.angle + deltaAngle
            )
        )
    }

    private func returnToOrbit() {
        guard selectedCardIndex != nil || selectionAnimationStartTime != nil else { return }
        orbitDragOffset += spinDragDelta
        spinDragDelta = 0
        selectedCardIndex = nil
        selectionAnimationStartTime = nil
        returnAnimationStartTime = Date()
        if let td = touchDownDate {
            let pauseDuration = Date().timeIntervalSince(td)
            animationStart = animationStart.addingTimeInterval(pauseDuration)
            touchDownDate = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dealTapUnlockDelay) {
            canSelect = true
        }
    }

    private func applyInertia(using value: DragGesture.Value) {
        let projectedDeltaX = value.predictedEndTranslation.width - value.translation.width
        let velocityTurns = Double(projectedDeltaX) / 220.0
        let distanceTurns = Double(value.translation.width) / 900.0
        let inertiaTurns = min(max(velocityTurns + distanceTurns, -4.5), 4.5)
        guard abs(inertiaTurns) >= 0.05 else { return }

        let duration = min(1.8, max(0.45, 0.55 + abs(inertiaTurns) * 0.25))
        withAnimation(.timingCurve(0.15, 0.90, 0.22, 1.00, duration: duration)) {
            orbitDragOffset += inertiaTurns
        }
    }

    private func orbitGalaxyCardState(for card: ProjectedGalaxyCard) -> SelectedGalaxyCardState {
        SelectedGalaxyCardState(
            offset: card.offset,
            scale: CGFloat(card.scale),
            tiltY: card.cardTiltY,
            tiltZ: 15,
            opacity: card.opacity,
            blur: CGFloat(card.blur)
        )
    }

    private func hitTestCard(at location: CGPoint, in size: CGSize, cards: [ProjectedGalaxyCard]) -> ProjectedGalaxyCard? {
        cards
            .filter { !$0.slot.isBlank }
            .sorted { $0.depth < $1.depth }
            .first { card in
                let side = 68.0 * CGFloat(card.scale) * 1.12
                let frame = CGRect(
                    x: size.width / 2 + card.offset.width - side / 2,
                    y: size.height / 2 + card.offset.height - side / 2,
                    width: side,
                    height: side
                )
                return frame.contains(location)
            }
    }

    private func projectedCards(elapsed: TimeInterval, extraDragOffset: Double = 0) -> [ProjectedGalaxyCard] {
        guard !slots.isEmpty else { return [] }

        let visibilityProgress = max(0.0001, Double(revealProgress))
        let count = slots.count
        let clampedVisibilityProgress = min(1.0, max(0.0, visibilityProgress))
        let orbitStep = 2.0 * .pi / Double(count)
        let dealProgress = min(1.0, max(0.0, elapsed / dealDuration))
        let orbitRad = (elapsed + orbitDragOffset + extraDragOffset) * orbitSpeed * .pi / 180.0
        let compressedSpan = compressedFanOrbitSteps * orbitStep
        let maxSlot = Double(max(count - 1, 1))

        var results: [ProjectedGalaxyCard] = []
        results.reserveCapacity(count)

        for (index, slot) in slots.enumerated() {
            let orbitRank = count - 1 - index
            let slotFraction = Double(index) / maxSlot

            let localDelay = Double(index) * dealStaggerPerCard / dealDuration
            let rawLocal = min(1.0, max(0.0, (dealProgress - localDelay) / max(1.0 - localDelay, 0.001)))
            let openProgress = galaxySmoothStep(rawLocal)

            let compressedOffset = compressedSpan / 2 - pow(slotFraction, compressedFanPower) * compressedSpan
            let finalOffset = Double(orbitRank) * orbitStep

            let angle = pileAngle + orbitRad + galaxyLerp(compressedOffset, finalOffset, openProgress)
            let p = GalaxyOrbit.project(angle: angle)

            let targetScale = 0.5 + 0.5 * p.depthScale
            let scale = targetScale * clampedVisibilityProgress + (1 - clampedVisibilityProgress) * 0.80
            let targetOpacity = min(1.0, 0.25 + 0.75 * p.depthScale)
            let opacity = targetOpacity * clampedVisibilityProgress + (1 - clampedVisibilityProgress) * 0.90
            let blur = max(0.0, (1.0 - p.depthScale) * 3.0)
            let zOrder = openProgress < depthZSwitchProgress ? Double(count - index) : -p.wz

            results.append(ProjectedGalaxyCard(
                id: slot.id,
                slot: slot,
                cardIndex: index,
                angle: angle,
                offset: CGSize(width: p.screenX, height: p.screenY),
                scale: scale,
                opacity: opacity,
                blur: blur,
                depth: p.wz,
                cardTiltY: p.cardTiltY,
                zOrder: zOrder
            ))
        }

        return results
    }
}

struct GalaxyAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(GalaxyAddButtonStyle())
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Add word")
    }
}

private struct GalaxyAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct GalaxyBlankCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isDarkMode ? Color.white.opacity(0.88) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(width: 66, height: 66)
            .shadow(color: Color.black.opacity(isDarkMode ? 0.28 : 0.08), radius: 4, x: 0, y: 2)
    }
}

struct GalaxySelectedCardTransitionRequest {
    let word: SimpleWord
    let sourceCardWidth: CGFloat
    let galaxyScale: CGFloat
    let rollStartAngle: Double
    let rollEndAngle: Double
}

func galaxySmoothStep(_ progress: Double) -> Double {
    let t = min(1.0, max(0.0, progress))
    return t * t * (3 - 2 * t)
}

func galaxyLerp(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
    start + (end - start) * CGFloat(progress)
}

func galaxyLerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
    start + (end - start) * progress
}

enum GalaxyOrbit {
    static let radius: Double = 135
    static let tiltX: Double = 18
    static let tiltZ: Double = 17
    static let camera: Double = 750

    private static let rxRad = tiltX * .pi / 180.0
    private static let rzRad = tiltZ * .pi / 180.0
    static let m00 = cos(rzRad)
    static let m02 = sin(rzRad) * sin(rxRad)
    static let m10 = sin(rzRad)
    static let m12 = -cos(rzRad) * sin(rxRad)
    static let m22 = cos(rxRad)

    struct Projection {
        let screenX: Double
        let screenY: Double
        let depthScale: Double
        let cardTiltY: Double
        let wz: Double
    }

    static func project(angle: Double) -> Projection {
        let cosA = cos(angle), sinA = sin(angle)
        let lx = cosA * radius
        let lz = sinA * radius
        let wx = m00 * lx + m02 * lz
        let wy = m10 * lx + m12 * lz
        let wz = m22 * lz
        let depthScale = camera / (camera + wz)
        return Projection(
            screenX: wx * depthScale,
            screenY: wy * depthScale,
            depthScale: depthScale,
            cardTiltY: -asin(sin(angle)) * 180.0 / .pi,
            wz: wz
        )
    }
}

func galaxyAccentBorder(isDarkMode: Bool) -> LinearGradient {
    LinearGradient(
        colors: isDarkMode
            ? [Color.white.opacity(0.28), Color.white.opacity(0.14)]
            : [Color.black.opacity(0.18), Color.black.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct SelectedGalaxyCardState {
    let offset: CGSize
    let scale: CGFloat
    let tiltY: Double
    let tiltZ: Double
    let opacity: Double
    let blur: CGFloat
}

struct ProjectedGalaxyCard: Identifiable {
    let id: String
    let slot: GalaxySlot
    let cardIndex: Int
    let angle: Double
    let offset: CGSize
    let scale: Double
    let opacity: Double
    let blur: Double
    let depth: Double
    let cardTiltY: Double
    let zOrder: Double
}

struct GalaxyWordCard: View {
    let word: SimpleWord
    var materialEnabled: Bool = true
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    init(word: SimpleWord, materialEnabled: Bool = true) {
        self.word = word
        self.materialEnabled = materialEnabled
    }

    private var title: String {
        let display = word.displayWord.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? word.word : display
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var titleFont: Font {
        switch appState.cardFontStyle {
        case .sfPro: return .system(size: 9.5, weight: .bold, design: .default)
        case .sfRounded: return .system(size: 9.5, weight: .bold, design: .rounded)
        case .avenirNext: return .custom("AvenirNext-Bold", size: 9.5)
        case .newYork: return .system(size: 9.5, weight: .bold, design: .serif)
        }
    }

    @ViewBuilder
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if materialEnabled || !isDarkMode {
            shape.themedGlassSurface(themeMode: appState.themeMode, isDarkMode: isDarkMode)
        } else {
            shape
                .fill(AppColors.elevatedSurfaceTint(themeMode: appState.themeMode, isDarkMode: isDarkMode))
                .overlay {
                    shape.fill(AppColors.elevatedSurfaceGlowStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode))
                }
                .overlay {
                    shape.fill(AppColors.elevatedSurfaceHighlightStyle(themeMode: appState.themeMode, isDarkMode: isDarkMode))
                }
                .overlay {
                    shape.stroke(AppColors.elevatedSurfaceBorder(themeMode: appState.themeMode, isDarkMode: isDarkMode), lineWidth: 1)
                }
                .overlay {
                    shape.inset(by: 1)
                        .stroke(AppColors.elevatedSurfaceInnerBorder(themeMode: appState.themeMode, isDarkMode: isDarkMode), lineWidth: 0.8)
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 6)
            Text(title)
                .font(titleFont)
                .tracking(0.12)
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.90) : Color.black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 2)
            Spacer(minLength: 0)
        }
        .frame(width: 56, height: 56, alignment: .topLeading)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(galaxyAccentBorder(isDarkMode: isDarkMode), lineWidth: 1.05)
        )
    }
}
