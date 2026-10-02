import SwiftUI

enum DiscoverCardLayout {
    static let horizontalInset: CGFloat = 20
    static let horizontalInsetTotal: CGFloat = horizontalInset * 2
    private static let cardBodyVerticalPaddingTotal: CGFloat = 48

    static func contentWidth(forScreenWidth width: CGFloat) -> CGFloat {
        max(width - horizontalInsetTotal, 0)
    }

    static func cardHeight(forCardWidth width: CGFloat) -> CGFloat {
        max(width - cardBodyVerticalPaddingTotal, 0)
    }

    static func restingCardYOffset(containerHeight: CGFloat) -> CGFloat {
        -min(56, max(36, containerHeight * 0.06))
    }

    static func keyboardDockingOffset(
        containerHeight: CGFloat,
        cardContentHeight: CGFloat,
        restingYOffset: CGFloat
    ) -> CGFloat {
        let visibleCardHeight = cardContentHeight + cardBodyVerticalPaddingTotal
        let currentCardBottom = containerHeight / 2 + restingYOffset + visibleCardHeight / 2
        let targetCardBottom = containerHeight - 18
        return max(0, targetCardBottom - currentCardBottom)
    }
}

struct ActiveCardHost: View {
    enum Phase: Equatable {
        case entering
        case presented
        case leaving
    }

    let word: SimpleWord
    let transitionRequest: GalaxySelectedCardTransitionRequest
    let phase: Phase
    let containerSize: CGSize
    let isActiveTab: Bool
    let onEnterComplete: () -> Void
    let onLeaveComplete: () -> Void

    @State private var phaseStart = Date()
    @State private var hasReportedPhase = false
    @State private var isCardInlineEditing = false

    private let enterDuration: Double = 0.48
    private let leaveDuration: Double = 0.34

    private var restingCardYOffset: CGFloat {
        DiscoverCardLayout.restingCardYOffset(containerHeight: containerSize.height)
    }
    private var restingCardContentHeight: CGFloat {
        DiscoverCardLayout.cardHeight(forCardWidth: containerSize.width)
    }

    var body: some View {
        Group {
            if phase == .presented {
                renderedCard(detailProgress: 1, state: Self.restingState, interactionEnabled: true)
            } else {
                TimelineView(.animation) { context in
                    let duration = phase == .entering ? enterDuration : leaveDuration
                    let raw = min(1.0, context.date.timeIntervalSince(phaseStart) / duration)
                    let progress = phase == .entering ? raw : 1 - raw
                    let detailProgress = transitionDetailProgress(progress: progress)
                    let state = transitionRenderState(progress: progress)
                    ZStack {
                        renderedCard(detailProgress: detailProgress, state: state, interactionEnabled: false)
                        if raw >= 1.0, !hasReportedPhase {
                            Color.clear
                                .frame(width: 0, height: 0)
                                .onAppear {
                                    hasReportedPhase = true
                                    if phase == .entering {
                                        onEnterComplete()
                                    } else {
                                        onLeaveComplete()
                                    }
                                }
                        }
                    }
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onAppear {
            phaseStart = Date()
            hasReportedPhase = false
        }
        .onChange(of: phase) { _, _ in
            phaseStart = Date()
            hasReportedPhase = false
            if phase == .leaving {
                isCardInlineEditing = false
            }
        }
    }

    private static let restingState = SelectedGalaxyCardState(offset: .zero, scale: 1, tiltY: 0, tiltZ: 0, opacity: 1, blur: 0)

    @ViewBuilder
    private func renderedCard(detailProgress: Double, state: SelectedGalaxyCardState, interactionEnabled: Bool) -> some View {
        let editingDockingOffset = isCardInlineEditing && interactionEnabled
            ? DiscoverCardLayout.keyboardDockingOffset(
                containerHeight: containerSize.height,
                cardContentHeight: restingCardContentHeight,
                restingYOffset: restingCardYOffset
            )
            : 0
        let cardYOffset = restingCardYOffset * CGFloat(detailProgress) + editingDockingOffset

        DiscoverCard(
            word: word,
            screenWidth: containerSize.width,
            screenHeight: containerSize.height,
            cardWidth: containerSize.width,
            cardHeight: restingCardContentHeight,
            isActiveTab: isActiveTab && interactionEnabled,
            detailProgress: detailProgress,
            contentOpacity: 1,
            interactionsEnabled: interactionEnabled,
            allowsInlineEditing: true,
            audioReactiveDividerEnabled: true,
            usesHomeSurfaceStyle: true,
            onInlineEditingChange: { editing in
                withAnimation(.easeOut(duration: editing ? 0.22 : 0.16)) {
                    isCardInlineEditing = editing
                }
            }
        )
        .id(word.id)
        .frame(width: containerSize.width, height: containerSize.height)
        .position(x: containerSize.width / 2, y: containerSize.height / 2 + cardYOffset)
        .allowsHitTesting(interactionEnabled)
        .rotation3DEffect(.degrees(state.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0)
        .rotationEffect(.degrees(state.tiltZ))
        .scaleEffect(state.scale)
        .offset(state.offset)
        .opacity(state.opacity)
        .modifier(ConditionalBlur(radius: state.blur))
    }

    private func transitionDetailProgress(progress: Double) -> Double {
        let t = min(1.0, max(0.0, (progress - 0.02) / 0.40))
        return galaxySmoothStep(t)
    }

    private func transitionRenderState(progress: Double) -> SelectedGalaxyCardState {
        let request = transitionRequest
        let eased = galaxySmoothStep(progress)
        let angle = galaxyLerp(request.rollStartAngle, request.rollEndAngle, eased)
        let base = orbitState(angle: angle, galaxyScale: request.galaxyScale)
        let currentWidth = request.sourceCardWidth * base.scale
        let settleT = galaxySmoothStep(min(1.0, max(0.0, (progress - 0.10) / 0.90)))
        let scaleT = galaxySmoothStep(min(1.0, max(0.0, (progress - 0.04) / 0.96)))
        let blurT = galaxySmoothStep(min(1.0, max(0.0, progress * 2.2)))

        return SelectedGalaxyCardState(
            offset: CGSize(
                width: galaxyLerp(base.offset.width, 0, settleT),
                height: galaxyLerp(base.offset.height, 0, settleT)
            ),
            scale: galaxyLerp(currentWidth / max(containerSize.width, 1), 1, scaleT),
            tiltY: galaxyLerp(base.tiltY, 0, settleT),
            tiltZ: galaxyLerp(base.tiltZ, 0, settleT),
            opacity: galaxyLerp(base.opacity, 1, settleT),
            blur: galaxyLerp(base.blur, 0, blurT)
        )
    }

    private func orbitState(angle: Double, galaxyScale: CGFloat) -> SelectedGalaxyCardState {
        let p = GalaxyOrbit.project(angle: angle)
        let scale = (0.5 + 0.5 * p.depthScale) * galaxyScale
        let opacity = min(1.0, 0.25 + 0.75 * p.depthScale)
        let blur = max(0.0, (1.0 - p.depthScale) * 3.0)

        return SelectedGalaxyCardState(
            offset: CGSize(width: p.screenX * galaxyScale, height: p.screenY * galaxyScale),
            scale: CGFloat(scale),
            tiltY: p.cardTiltY,
            tiltZ: 15,
            opacity: opacity,
            blur: CGFloat(blur)
        )
    }
}
