import SwiftUI
import Combine
import AVFoundation
#if os(iOS)
import UIKit
import CoreMotion
#endif

struct PillSelector: View {
    enum VisualStyle {
        case standard
        case glossy
    }

    let labels: [String]
    let symbols: [String]?
    let selectedIndex: Int
    let verticalPadding: CGFloat
    let style: VisualStyle
    let onSelect: (Int) -> Void
    private let controlHeight: CGFloat
    private let glossyIndicatorVInset: CGFloat?
    private let glossyIndicatorHInset: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    init(
        labels: [String],
        symbols: [String]? = nil,
        selectedIndex: Int,
        verticalPadding: CGFloat = 9,
        controlHeight: CGFloat = 52,
        glossyIndicatorVerticalInset: CGFloat? = nil,
        glossyIndicatorHorizontalInset: CGFloat? = nil,
        style: VisualStyle = .standard,
        onSelect: @escaping (Int) -> Void
    ) {
        self.labels = labels
        self.symbols = symbols
        self.selectedIndex = selectedIndex
        self.verticalPadding = verticalPadding
        self.controlHeight = controlHeight
        self.glossyIndicatorVInset = glossyIndicatorVerticalInset
        self.glossyIndicatorHInset = glossyIndicatorHorizontalInset
        self.style = style
        self.onSelect = onSelect
    }

    private var clampedSelectedIndex: Int {
        guard !labels.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), labels.count - 1)
    }

    private var selectedForeground: Color {
        switch style {
        case .glossy:
            return colorScheme == .dark
                ? Color.white.opacity(0.92)
                : Color.black.opacity(0.82)
        case .standard:
            return colorScheme == .dark
                ? Color(red: 0.42, green: 0.86, blue: 0.36)
                : Color(red: 0.04, green: 0.40, blue: 0.12)
        }
    }

    private var unselectedForeground: Color {
        switch style {
        case .glossy:
            return colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.40)
        case .standard:
            return colorScheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.42)
        }
    }

    private var trackBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.60)
    }

    private var indicatorBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.90)
    }

    @ViewBuilder
    private func segmentLabel(at idx: Int) -> some View {
        if let symbols, symbols.indices.contains(idx) {
            Image(systemName: symbols[idx])
                .font(.system(size: 13, weight: .semibold))
                .symbolEffect(.bounce, options: .nonRepeating, value: clampedSelectedIndex == idx)
        } else {
            Text(labels[idx])
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
    }

    private func glossySelectedIndicator() -> some View {
        let edgeGradient = LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.38 : 0.75),
                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return Capsule()
            .fill(.regularMaterial)
            .overlay(
                Capsule()
                    .stroke(edgeGradient, lineWidth: 1)
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), lineWidth: 0.5)
                    .padding(-0.4)
            )
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.45)
                        )
                    )
                    .padding(2)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.12), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 1.5, x: 0, y: 0.5)
    }

    private var indicatorHorizontalInset: CGFloat {
        if style == .glossy, let h = glossyIndicatorHInset {
            return h
        }
        switch style {
        case .glossy:
            return colorScheme == .dark ? 3.5 : 4
        case .standard:
            return 4
        }
    }

    private var indicatorVerticalInset: CGFloat {
        if style == .glossy, let v = glossyIndicatorVInset {
            return v
        }
        switch style {
        case .glossy:
            return colorScheme == .dark ? 3.5 : 3
        case .standard:
            return 3
        }
    }

    @ViewBuilder
    private func slidingIndicator(width: CGFloat, height: CGFloat) -> some View {
        Group {
            switch style {
            case .glossy:
                glossySelectedIndicator()
            case .standard:
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule()
                            .stroke(indicatorBorderColor, lineWidth: 0.8)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12),
                        radius: 4, x: 0, y: 2
                    )
            }
        }
        .frame(width: width, height: height)
        .compositingGroup()
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(labels.count, 1)
            let segW = geo.size.width / CGFloat(count)
            let hInset = indicatorHorizontalInset
            let vInset = indicatorVerticalInset
            let indW = max(0, segW - hInset * 2)
            let indH = max(0, geo.size.height - vInset * 2)
            ZStack(alignment: .topLeading) {
                slidingIndicator(width: indW, height: indH)
                    .offset(
                        x: CGFloat(clampedSelectedIndex) * segW + hInset,
                        y: vInset
                    )
                HStack(spacing: 0) {
                    ForEach(labels.indices, id: \.self) { idx in
                        segmentLabel(at: idx)
                            .foregroundStyle(idx == clampedSelectedIndex ? selectedForeground : unselectedForeground)
                            .padding(.vertical, verticalPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(idx) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .padding(4)
        .background(
            Group {
                switch style {
                case .glossy:
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45),
                                    lineWidth: 0.75
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), lineWidth: 0.5)
                                .padding(-0.35)
                        )
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.07),
                            radius: 3, x: 0, y: 1.5
                        )
                case .standard:
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(trackBorderColor, lineWidth: 0.8)
                        )
                }
            }
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.92), value: clampedSelectedIndex)
        .animation(.easeInOut(duration: 0.30), value: colorScheme)
        .sensoryFeedback(.selection, trigger: clampedSelectedIndex)
        .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight)
        .padding(.horizontal, 7)
    }
}

