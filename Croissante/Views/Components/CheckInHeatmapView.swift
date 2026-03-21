import SwiftUI

struct CheckInHeatmapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var srsManager: SRSManager
    @State private var autoReturnTask: Task<Void, Never>?
    @State private var initialCenterTask: Task<Void, Never>?
    @State private var hasCenteredOnAppear = false
    @State private var lastTickTranslationX: CGFloat = 0
    @State private var todayDotBlink = false

    private let calendar: Calendar
    private let today: Date

    private let cellSize: CGFloat = 15
    private let cellSpacing: CGFloat = 4
    private let gearTickStep: CGFloat = 14
    private let monthHeaderHeight: CGFloat = 20
    private let weeks: [WeekColumn]
    private let monthMarkers: [MonthMarker]

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        var configuredCalendar = calendar
        configuredCalendar.locale = Locale(identifier: "en_US_POSIX")
        configuredCalendar.firstWeekday = 1 // GitHub style: Sunday-first columns

        self.calendar = configuredCalendar
        self.today = configuredCalendar.startOfDay(for: referenceDate)

        let year = configuredCalendar.component(.year, from: self.today)

        let startOfYear = configuredCalendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? self.today
        let endOfYear = configuredCalendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? self.today
        let firstWeekStart = configuredCalendar.dateInterval(of: .weekOfYear, for: startOfYear)?.start ?? startOfYear
        let lastWeekStart = configuredCalendar.dateInterval(of: .weekOfYear, for: endOfYear)?.start ?? endOfYear

        let generatedWeeks = Self.buildWeeks(
            calendar: configuredCalendar,
            firstWeekStart: firstWeekStart,
            lastWeekStart: lastWeekStart
        )
        self.weeks = generatedWeeks
        self.monthMarkers = Self.buildMonthMarkers(
            year: year,
            firstWeekStart: firstWeekStart,
            weeksCount: generatedWeeks.count,
            calendar: configuredCalendar
        )
    }

    private var gridWidth: CGFloat {
        CGFloat(weeks.count) * cellSize + CGFloat(max(0, weeks.count - 1)) * cellSpacing
    }
    
    private var todayWeekIndex: Int? {
        weeks.first { week in
            week.days.contains { day in
                calendar.isDate(day, inSameDayAs: today)
            }
        }?.index
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
        srsManager.todayStudyState == .inProgress && srsManager.todayMasteryProgressRatio < 0.20
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.70)
    }

    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.85)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    monthHeader
                    contributionGrid
                }
                .padding(.vertical, 2)
            }
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(panelBorderColor, lineWidth: 1)
            )
            .onAppear {
                FeedbackService.prepareInteractive()
                if !hasCenteredOnAppear {
                    hasCenteredOnAppear = true
                    scheduleInitialCenter(using: proxy)
                }
                updateTodayDotBlinking()
            }
            .onChange(of: shouldBlinkTodayDot) { _, _ in
                updateTodayDotBlinking()
            }
            .onDisappear {
                cancelAutoReturn()
                cancelInitialCenter()
                hasCenteredOnAppear = false
                stopTodayDotBlinking()
            }
        }
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
        guard let todayWeekIndex else { return }

        autoReturnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.30)) {
                proxy.scrollTo(todayWeekIndex, anchor: .center)
            }
        }
    }

    private func cancelInitialCenter() {
        initialCenterTask?.cancel()
        initialCenterTask = nil
    }

    private func scheduleInitialCenter(using proxy: ScrollViewProxy) {
        cancelInitialCenter()
        guard todayWeekIndex != nil else { return }

        initialCenterTask = Task { @MainActor in
            centerOnToday(using: proxy, animated: false)

            // First layout pass can still shift content on hot reload/startup.
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            centerOnToday(using: proxy, animated: false)
        }
    }

    private func centerOnToday(using proxy: ScrollViewProxy, animated: Bool) {
        guard let todayWeekIndex else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.30)) {
                proxy.scrollTo(todayWeekIndex, anchor: .center)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(todayWeekIndex, anchor: .center)
            }
        }
    }

    private var monthHeader: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: gridWidth, height: monthHeaderHeight)

            ForEach(monthMarkers) { marker in
                Text(marker.title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(monthTextColor)
                    .offset(x: CGFloat(marker.weekIndex) * (cellSize + cellSpacing))
            }
        }
    }

    private var contributionGrid: some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(weeks) { week in
                VStack(spacing: cellSpacing) {
                    ForEach(week.days, id: \.self) { day in
                        dayCell(for: day)
                    }
                }
                .id(week.index)
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let ratio = srsManager.masteryProgressRatio(for: date)
        let state = srsManager.studyState(for: date)

        let fillColor: Color
        let showTodayDot: Bool
        let showTodayBorder: Bool

        switch state {
        case .completed:
            fillColor = deepGreenCellColor
            showTodayDot = false
            showTodayBorder = false
        case .inProgress:
            if ratio >= 0.70 {
                fillColor = mediumGreenCellColor
                showTodayDot = false
                showTodayBorder = false
            } else if ratio >= 0.20 {
                fillColor = lightGreenCellColor
                showTodayDot = false
                showTodayBorder = false
            } else if isToday {
                fillColor = cellBackgroundColor
                showTodayDot = true
                showTodayBorder = true
            } else {
                fillColor = cellBackgroundColor
                showTodayDot = false
                showTodayBorder = false
            }
        case .noEligibleCards:
            fillColor = cellBackgroundColor
            showTodayDot = false
            showTodayBorder = false
        }

        let glowColor: Color?
        if colorScheme == .dark {
            switch state {
            case .completed:
                glowColor = deepGreenCellColor
            case .inProgress where ratio >= 0.70:
                glowColor = mediumGreenCellColor
            case .inProgress where ratio >= 0.20:
                glowColor = lightGreenCellColor
            default:
                glowColor = nil
            }
        } else {
            glowColor = nil
        }

        let glowLayerColor = glowColor ?? .clear
        let showGlow = glowColor != nil

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if let glowColor {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(glowColor.opacity(0.88), lineWidth: 0.9)
                        .blur(radius: 0.8)
                }
            }
            .overlay(alignment: .center) {
                if showTodayDot {
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
                    .stroke(todayBorderColor, lineWidth: showTodayBorder ? 1 : 0)
            )
            .shadow(color: showGlow ? glowLayerColor.opacity(0.58) : .clear, radius: showGlow ? 2.6 : 0, x: 0, y: 0)
            .shadow(color: showGlow ? glowLayerColor.opacity(0.30) : .clear, radius: showGlow ? 6.2 : 0, x: 0, y: 0)
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
