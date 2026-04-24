import SwiftUI

struct CheckInHeatmapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var srsManager: SRSManager
    @State private var autoReturnTask: Task<Void, Never>?
    @State private var initialCenterTask: Task<Void, Never>?
    @State private var heatmapPressTask: Task<Void, Never>?
    @State private var heatmapPressProgress: CGFloat?
    @State private var lastViewportWidth: CGFloat = 0
    @State private var lastTickTranslationX: CGFloat = 0
    @State private var todayDotBlink = false

    private let isActive: Bool
    private let calendar: Calendar

    private let cellSize: CGFloat = 15
    private let cellSpacing: CGFloat = 4
    private let horizontalPanelPadding: CGFloat = 10
    private let gearTickStep: CGFloat = 14
    private let monthHeaderHeight: CGFloat = 20
    private let heatmapPressDuration: TimeInterval = 4.00
    private let heatmapPressPause: TimeInterval = 3.00
    private let heatmapPressFrameRate: Double = 36
    private let heatmapPressBandHalfWidth: CGFloat = 0.65
    private let heatmapPressArchLift: CGFloat = 3.80
    private let heatmapPressScaleReduction: CGFloat = 0.42

    init(isActive: Bool = true, calendar: Calendar = .current) {
        var configuredCalendar = calendar
        configuredCalendar.locale = Locale(identifier: "en_US_POSIX")
        configuredCalendar.firstWeekday = 1 // GitHub style: Sunday-first columns

        self.isActive = isActive
        self.calendar = configuredCalendar
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var monthTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.74) : Color.black.opacity(0.82)
    }

    private var cellBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(red: 0.92, green: 0.93, blue: 0.94)
    }

    private var todayDotColor: Color {
        Color(red: 0.19, green: 0.73, blue: 0.46)
    }

    private var lightGreenCellColor: Color {
        Color(red: 0.72, green: 0.92, blue: 0.79)
    }

    private var mediumGreenCellColor: Color {
        Color(red: 0.40, green: 0.78, blue: 0.53)
    }

    private var deepGreenCellColor: Color {
        Color(red: 0.15, green: 0.58, blue: 0.33)
    }

    private var todayBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.10)
    }

    private var shouldBlinkTodayDot: Bool {
        srsManager.todayStudyState == .inProgress && srsManager.todayDeckCompletionRatio < 0.20
    }

    private var shouldRunHeatmapAnimations: Bool {
        isActive && scenePhase == .active && !reduceMotion
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.70)
    }

    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.85)
    }

    var body: some View {
        let layout = makeYearLayout()
        let gridW = gridWidth(for: layout.weeks)
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: sideInset(for: geometry.size.width, gridWidth: gridW))
                        VStack(alignment: .leading, spacing: 8) {
                            monthHeader(layout: layout)
                            contributionGrid(layout: layout)
                        }
                        .padding(.vertical, 2)
                        Color.clear.frame(width: sideInset(for: geometry.size.width, gridWidth: gridW))
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            cancelAutoReturn()
                            triggerGearTickIfNeeded(for: value.translation)
                        }
                        .onEnded { value in
                            lastTickTranslationX = 0
                            guard abs(value.translation.width) > abs(value.translation.height),
                                  abs(value.translation.width) > 8 else { return }
                            scheduleAutoReturn(using: proxy)
                        }
                )
                .padding(.horizontal, horizontalPanelPadding)
                .padding(.vertical, 8)
                .background(panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(panelBorderColor, lineWidth: 1)
                )
                .onAppear {
                    FeedbackService.prepareInteractive()
                    lastViewportWidth = geometry.size.width
                    scheduleInitialCenter(using: proxy)
                    updateHeatmapAnimations()
                }
                .onChange(of: shouldBlinkTodayDot) { _, _ in
                    updateHeatmapAnimations()
                }
                .onChange(of: reduceMotion) { _, _ in
                    updateHeatmapAnimations()
                }
                .onChange(of: scenePhase) { _, _ in
                    updateHeatmapAnimations()
                }
                .onChange(of: isActive) { _, _ in
                    updateHeatmapAnimations()
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    guard abs(newWidth - lastViewportWidth) > 0.5 else { return }
                    lastViewportWidth = newWidth
                    scheduleInitialCenter(using: proxy)
                }
                .onDisappear {
                    cancelAutoReturn()
                    cancelInitialCenter()
                    lastViewportWidth = 0
                    stopTodayDotBlinking()
                    stopHeatmapPress()
                }
            }
        }
    }

    private func updateHeatmapAnimations() {
        if shouldRunHeatmapAnimations {
            updateTodayDotBlinking()
            startHeatmapPressIfNeeded()
        } else {
            stopTodayDotBlinking()
            stopHeatmapPress()
        }
    }

    private func startHeatmapPressIfNeeded() {
        guard shouldRunHeatmapAnimations else { return }
        guard heatmapPressTask == nil else { return }

        heatmapPressTask = Task { @MainActor in
            while !Task.isCancelled {
                await runHeatmapPress()
                guard !Task.isCancelled else { break }

                setHeatmapPressProgress(nil)

                try? await Task.sleep(nanoseconds: nanoseconds(for: heatmapPressPause))
            }
        }
    }

    private func runHeatmapPress() async {
        setHeatmapPressProgress(0)

        let frameCount = max(1, Int((heatmapPressDuration * heatmapPressFrameRate).rounded(.up)))
        let frameDuration = heatmapPressDuration / Double(frameCount)
        let frameNanoseconds = nanoseconds(for: frameDuration)

        for frame in 0...frameCount {
            guard !Task.isCancelled else { break }
            heatmapPressProgress = CGFloat(frame) / CGFloat(frameCount)
            try? await Task.sleep(nanoseconds: frameNanoseconds)
        }
    }

    private func stopHeatmapPress() {
        heatmapPressTask?.cancel()
        heatmapPressTask = nil

        setHeatmapPressProgress(nil)
    }

    private func setHeatmapPressProgress(_ progress: CGFloat?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            heatmapPressProgress = progress
        }
    }

    private func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64((duration * 1_000_000_000).rounded())
    }

    private func sideInset(for containerWidth: CGFloat, gridWidth: CGFloat) -> CGFloat {
        let visibleWidth = max(0, containerWidth - (horizontalPanelPadding * 2))
        let slack = visibleWidth - gridWidth
        if slack > 0 {
            return slack / 2
        }
        return horizontalPanelPadding
    }

    private func triggerGearTickIfNeeded(for translation: CGSize) {
        guard abs(translation.width) > abs(translation.height) else { return }

        let deltaX = translation.width - lastTickTranslationX
        guard abs(deltaX) >= gearTickStep else { return }

        let steps = Int(abs(deltaX) / gearTickStep)
        guard steps > 0 else { return }
        FeedbackService.gearTick(steps: steps)

        let direction: CGFloat = deltaX >= 0 ? 1 : -1
        lastTickTranslationX += CGFloat(steps) * gearTickStep * direction
    }

    private func updateTodayDotBlinking() {
        guard shouldBlinkTodayDot else {
            stopTodayDotBlinking()
            return
        }
        guard !todayDotBlink else { return }
        todayDotBlink = false
        withAnimation(.easeInOut(duration: 0.90).repeatForever(autoreverses: true)) {
            todayDotBlink = true
        }
    }

    private func stopTodayDotBlinking() {
        guard todayDotBlink else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            todayDotBlink = false
        }
    }

    private func cancelAutoReturn() {
        autoReturnTask?.cancel()
        autoReturnTask = nil
    }

    private func scheduleAutoReturn(using proxy: ScrollViewProxy) {
        cancelAutoReturn()
        let layout = makeYearLayout()
        guard let todayWeekIndex = todayWeekIndex(in: layout) else { return }
        let todayId = dayID(today)

        autoReturnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            let anchor = scrollAnchor(for: todayWeekIndex, weeksCount: layout.weeks.count)
            withAnimation(.easeInOut(duration: 0.30)) {
                proxy.scrollTo(todayId, anchor: anchor)
            }
        }
    }

    private func cancelInitialCenter() {
        initialCenterTask?.cancel()
        initialCenterTask = nil
    }

    private func scheduleInitialCenter(using proxy: ScrollViewProxy) {
        cancelInitialCenter()
        let layout = makeYearLayout()
        guard todayWeekIndex(in: layout) != nil else { return }

        initialCenterTask = Task { @MainActor in
            centerOnToday(using: proxy, animated: false)

            // First layout pass can still shift content on hot reload/startup.
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            centerOnToday(using: proxy, animated: false)
        }
    }

    private func centerOnToday(using proxy: ScrollViewProxy, animated: Bool) {
        let layout = makeYearLayout()
        guard let todayWeekIndex = todayWeekIndex(in: layout) else { return }
        let todayId = dayID(today)
        let anchor = scrollAnchor(for: todayWeekIndex, weeksCount: layout.weeks.count)
        if animated {
            withAnimation(.easeInOut(duration: 0.30)) {
                proxy.scrollTo(todayId, anchor: anchor)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(todayId, anchor: anchor)
            }
        }
    }

    private func scrollAnchor(for weekIndex: Int, weeksCount: Int) -> UnitPoint {
        let visibleWidth = max(0, lastViewportWidth - (horizontalPanelPadding * 2))
        let weekSpan = cellSize + cellSpacing
        guard visibleWidth > 0, weekSpan > 0 else { return .center }

        let visibleWeeks = max(1, Int((visibleWidth + cellSpacing) / weekSpan))
        guard weeksCount > visibleWeeks else { return .center }

        let edgeThreshold = max(1, visibleWeeks / 2)
        if weekIndex <= edgeThreshold {
            return .leading
        }
        if weekIndex >= (weeksCount - 1 - edgeThreshold) {
            return .trailing
        }
        return .center
    }

    private func monthHeader(layout: YearLayout) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: gridWidth(for: layout.weeks), height: monthHeaderHeight)

            ForEach(layout.monthMarkers) { marker in
                Text(marker.title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(monthTextColor)
                    .offset(x: CGFloat(marker.weekIndex) * (cellSize + cellSpacing))
            }
        }
    }

    private func contributionGrid(layout: YearLayout) -> some View {
        let activeTodayWeekIndex = todayWeekIndex(in: layout) ?? max(0, layout.weeks.count - 1)
        let visibleWeekCount = estimatedVisibleWeekCount(totalWeeks: layout.weeks.count)

        return HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(layout.weeks) { week in
                VStack(spacing: cellSpacing) {
                    ForEach(Array(week.days.enumerated()), id: \.element) { dayIndex, day in
                        dayCell(
                            for: day,
                            displayYear: layout.displayYear,
                            weekIndex: week.index,
                            dayIndex: dayIndex,
                            todayWeekIndex: activeTodayWeekIndex,
                            visibleWeekCount: visibleWeekCount
                        )
                            .id(dayID(day))
                    }
                }
                .id(week.index)
            }
        }
    }

    @ViewBuilder
    private func dayCell(
        for date: Date,
        displayYear: Int,
        weekIndex: Int,
        dayIndex: Int,
        todayWeekIndex: Int,
        visibleWeekCount: CGFloat
    ) -> some View {
        let isInDisplayYear = calendar.component(.year, from: date) == displayYear
        if !isInDisplayYear {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        } else {
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let ratio = srsManager.deckCompletionRatio(for: date)
            let appearance = heatmapCellAppearance(
                for: srsManager.studyState(for: date),
                ratio: ratio,
                isToday: isToday
            )
            let glowLayerColor = appearance.glowColor ?? .clear
            let showGlow = appearance.glowColor != nil
            let pressAmount = heatmapPressAmount(
                weekIndex: weekIndex,
                dayIndex: dayIndex,
                todayWeekIndex: todayWeekIndex,
                visibleWeekCount: visibleWeekCount
            )
            let pressScale = 1 - heatmapPressScaleReduction * pressAmount
            let pressLightenOpacity = appearance.isColored ? (colorScheme == .dark ? 0.58 : 0.68) * pressAmount : 0
            let pressedShadowMultiplier = max(0.18, 1 - pressAmount * 0.76)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(appearance.fillColor)
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if let glowColor = appearance.glowColor {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(glowColor.opacity(0.88), lineWidth: 0.9)
                            .blur(radius: 0.8)
                    }
                }
                .overlay {
                    if pressLightenOpacity > 0.001 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(pressLightenOpacity))
                    }
                }
                .overlay(alignment: .center) {
                    if appearance.showTodayDot {
                        ZStack {
                            Circle()
                                .fill(todayDotColor.opacity(colorScheme == .dark ? 0.34 : 0.28))
                                .frame(width: 9.6, height: 9.6)
                                .blur(radius: 1.2)
                                .opacity(todayDotBlink ? 1.0 : 0.46)
                                .scaleEffect(todayDotBlink ? 1.0 : 0.80)
                            Circle()
                                .fill(todayDotColor.opacity(colorScheme == .dark ? 0.50 : 0.38))
                                .frame(width: 6.8, height: 6.8)
                                .blur(radius: 0.45)
                                .opacity(todayDotBlink ? 1.0 : 0.58)
                                .scaleEffect(todayDotBlink ? 1.0 : 0.88)
                            Circle()
                                .fill(todayDotColor)
                                .frame(width: 3.8, height: 3.8)
                        }
                        .shadow(color: todayDotColor.opacity(colorScheme == .dark ? 0.38 : 0.26), radius: 2.8, x: 0, y: 0)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(todayBorderColor, lineWidth: appearance.showTodayBorder ? 1 : 0)
                )
                .scaleEffect(pressScale)
                .animation(.spring(response: 0.18, dampingFraction: 0.70, blendDuration: 0.03), value: pressAmount > 0.001)
                .shadow(color: showGlow ? glowLayerColor.opacity(0.58 * pressedShadowMultiplier) : .clear, radius: showGlow ? 2.6 * pressedShadowMultiplier : 0, x: 0, y: 0)
                .shadow(color: showGlow ? glowLayerColor.opacity(0.30 * pressedShadowMultiplier) : .clear, radius: showGlow ? 6.2 * pressedShadowMultiplier : 0, x: 0, y: 0)
        }
    }

    private func heatmapCellAppearance(
        for state: SRSManager.DailyStudyState,
        ratio: Double,
        isToday: Bool
    ) -> HeatmapCellAppearance {
        let fillColor: Color
        let showTodayDot: Bool
        let showTodayBorder: Bool
        let isColored: Bool

        switch state {
        case .completed:
            fillColor = deepGreenCellColor
            showTodayDot = false
            showTodayBorder = false
            isColored = true
        case .inProgress:
            if ratio >= 0.70 {
                fillColor = mediumGreenCellColor
                showTodayDot = false
                showTodayBorder = false
                isColored = true
            } else if ratio >= 0.20 {
                fillColor = lightGreenCellColor
                showTodayDot = false
                showTodayBorder = false
                isColored = true
            } else if isToday {
                fillColor = cellBackgroundColor
                showTodayDot = true
                showTodayBorder = true
                isColored = false
            } else {
                fillColor = cellBackgroundColor
                showTodayDot = false
                showTodayBorder = false
                isColored = false
            }
        case .noEligibleCards:
            fillColor = cellBackgroundColor
            showTodayDot = false
            showTodayBorder = false
            isColored = false
        }

        return HeatmapCellAppearance(
            fillColor: fillColor,
            showTodayDot: showTodayDot,
            showTodayBorder: showTodayBorder,
            isColored: isColored,
            glowColor: colorScheme == .dark && isColored ? fillColor : nil
        )
    }

    private func estimatedVisibleWeekCount(totalWeeks: Int) -> CGFloat {
        let visibleWidth = max(0, lastViewportWidth - (horizontalPanelPadding * 2))
        let weekSpan = cellSize + cellSpacing
        guard visibleWidth > 0, weekSpan > 0 else {
            return min(CGFloat(totalWeeks), 18)
        }

        return min(CGFloat(totalWeeks), max(8, (visibleWidth + cellSpacing) / weekSpan))
    }

    private func heatmapPressAmount(
        weekIndex: Int,
        dayIndex: Int,
        todayWeekIndex: Int,
        visibleWeekCount: CGFloat
    ) -> CGFloat {
        guard !reduceMotion, let progress = heatmapPressProgress else { return 0 }

        let normalizedProgress = min(max(progress, 0), 1)
        let visibleMinX = CGFloat(todayWeekIndex) - visibleWeekCount / 2
        let visibleMaxX = CGFloat(todayWeekIndex) + visibleWeekCount / 2
        let visibleRange = max(visibleMaxX - visibleMinX, 1)
        let bottomY: CGFloat = 6
        let topY: CGFloat = 0
        let startProjection = visibleMinX - bottomY
        let endProjection = visibleMaxX - topY
        let bandCenterProjection = startProjection + (endProjection - startProjection) * normalizedProgress
        let xProgress = min(max((CGFloat(weekIndex) - visibleMinX) / visibleRange, 0), 1)
        let archLift = CGFloat(sin(Double(xProgress) * .pi)) * heatmapPressArchLift
        let cellProjection = CGFloat(weekIndex) - CGFloat(dayIndex) - archLift

        return abs(cellProjection - bandCenterProjection) <= heatmapPressBandHalfWidth ? 1 : 0
    }

    private func makeYearLayout() -> YearLayout {
        let displayYear = calendar.component(.year, from: today)
        let startOfYear = calendar.date(from: DateComponents(year: displayYear, month: 1, day: 1)) ?? today
        let endOfYear = calendar.date(from: DateComponents(year: displayYear, month: 12, day: 31)) ?? today
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: startOfYear)?.start ?? startOfYear
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: endOfYear)?.start ?? endOfYear
        let weeks = Self.buildWeeks(
            calendar: calendar,
            firstWeekStart: firstWeekStart,
            lastWeekStart: lastWeekStart
        )
        let monthMarkers = Self.buildMonthMarkers(
            year: displayYear,
            firstWeekStart: firstWeekStart,
            weeksCount: weeks.count,
            calendar: calendar
        )
        return YearLayout(displayYear: displayYear, weeks: weeks, monthMarkers: monthMarkers)
    }

    private func gridWidth(for weeks: [WeekColumn]) -> CGFloat {
        CGFloat(weeks.count) * cellSize + CGFloat(max(0, weeks.count - 1)) * cellSpacing
    }

    private func todayWeekIndex(in layout: YearLayout) -> Int? {
        layout.weeks.first { week in
            week.days.contains { day in
                calendar.isDate(day, inSameDayAs: today)
            }
        }?.index
    }

    private func dayID(_ date: Date) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSince1970)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static func buildWeeks(calendar: Calendar, firstWeekStart: Date, lastWeekStart: Date) -> [WeekColumn] {
        var result: [WeekColumn] = []
        var weekStart = firstWeekStart
        var weekIndex = 0

        while weekStart <= lastWeekStart {
            let days = (0..<7).compactMap { dayOffset in
                calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
            }
            result.append(WeekColumn(index: weekIndex, startDate: weekStart, days: days))
            weekIndex += 1
            weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 24 * 60 * 60)
        }

        return result
    }

    private static func buildMonthMarkers(year: Int, firstWeekStart: Date, weeksCount: Int, calendar: Calendar) -> [MonthMarker] {
        var markers: [MonthMarker] = []
        for month in 1...12 {
            guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let monthWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start else {
                continue
            }

            let dayDistance = calendar.dateComponents([.day], from: firstWeekStart, to: monthWeekStart).day ?? 0
            let weekIndex = max(0, dayDistance / 7)

            guard weekIndex < weeksCount else { continue }
            markers.append(MonthMarker(weekIndex: weekIndex, title: monthFormatter.string(from: monthStart)))
        }

        return markers
    }
}

private struct YearLayout {
    let displayYear: Int
    let weeks: [WeekColumn]
    let monthMarkers: [MonthMarker]
}

private struct HeatmapCellAppearance {
    let fillColor: Color
    let showTodayDot: Bool
    let showTodayBorder: Bool
    let isColored: Bool
    let glowColor: Color?
}

private struct WeekColumn: Identifiable {
    let index: Int
    let startDate: Date
    let days: [Date]

    var id: Int { index }
}

private struct MonthMarker: Identifiable {
    let weekIndex: Int
    let title: String

    var id: Int { weekIndex }
}
