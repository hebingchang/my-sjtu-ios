//
//  MySJTUWidget.swift
//  MySJTUWidget
//
//  Created by boar on 2024/11/25.
//

import WidgetKit
import SwiftUI
import GRDB
import UIKit

// MARK: - Constants

private enum WidgetConstants {
    static let timeFormat = "H:mm"
    static let defaultCollegeId = 1
    static let appGroupIdentifier = UserDefaults.appGroupIdentifier
    static let databaseName = "class_table.db"
}

private enum WidgetCopy {
    static let current = "当前"
    static let noSchedules = "今天没有课程"
    static let allSchedulesFinished = "已上完全部课程"
    static let placeholderTitle = "这个文本框是课程名称的占位符"
    static let placeholderSubtitle = "这里是地点"
}

private enum WidgetLayout {
    static let cardCornerRadius: CGFloat = 24
    static let colorMarkCornerRadius: CGFloat = 2
    static let colorMarkSize: CGFloat = 10
}

private enum WidgetScheduleListLayout {
    static let cardPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 6
    static let dividerVerticalPadding: CGFloat = 8
}

private enum WidgetBackgroundLayout {
    static let imageScale: CGFloat = 1.05
}

enum WidgetCardSurfaceContrastStyle {
    case standard
    case elevated
}

private enum WidgetCardSurfaceLayout {
    static let borderWidth: CGFloat = 1
    static let highlightBorderWidth: CGFloat = 1.5
    static let accentWidth: CGFloat = 4
    static let accentHeight: CGFloat = 26
    static let accentInset: CGFloat = 10
    static let accentVerticalInset: CGFloat = 10
    static let shadowRadius: CGFloat = 14
    static let shadowYOffset: CGFloat = 8
}

// MARK: - Models

struct WidgetSchedule: Hashable {
    let start: String
    let end: String
    let name: String
    let location: String
    let color: String?
}

private extension WidgetSchedule {
    var startSortKey: (hour: Int, minute: Int) {
        let components = start.split(separator: ":")
        return (hour: Int(components[0])!, minute: Int(components[1])!)
    }

    func isBefore(_ other: WidgetSchedule) -> Bool {
        let selfKey = startSortKey
        let otherKey = other.startSortKey

        if selfKey.hour != otherKey.hour {
            return selfKey.hour < otherKey.hour
        }

        return selfKey.minute < otherKey.minute
    }

    func startDate(on date: Date) -> Date {
        date.timeOfDay(WidgetConstants.timeFormat, timeStr: start)!
    }

    func endDate(on date: Date) -> Date {
        date.timeOfDay(WidgetConstants.timeFormat, timeStr: end)!
    }

    func isCurrent(at date: Date) -> Bool {
        startDate(on: date) <= date
    }

    func startLabel(at date: Date) -> String {
        isCurrent(at: date) ? WidgetCopy.current : start
    }
}

enum DailyStatus: Equatable {
    case loading
    case hasSchedules
    case noSchedules
    case allSchedulesFinished
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let schedules: [WidgetSchedule]?
    let semester: Semester?
    let status: DailyStatus
}

private extension ScheduleEntry {
    var firstSchedule: WidgetSchedule? {
        schedules?.first
    }

    var emptyStateText: String {
        status == .noSchedules ? WidgetCopy.noSchedules : WidgetCopy.allSchedulesFinished
    }
}

// MARK: - Provider

struct Provider: TimelineProvider {
    private struct CollegeSelection {
        let primaryCollege: College
        let colleges: [College]
    }

    private struct LoadedScheduleData {
        let semester: Semester?
        let courseSchedules: [ScheduleInfo]
        let customSchedules: [CustomSchedule]
    }

    /// Returns an initialized database pool at the shared location databaseURL,
    /// or nil if the database is not created yet, or does not have the required
    /// schema version.
    private func openSharedReadOnlyDatabase(at databaseURL: URL) throws -> DatabasePool? {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var dbPool: DatabasePool?
        var dbError: Error?

        coordinator.coordinate(readingItemAt: databaseURL, options: .withoutChanges, error: &coordinatorError) { url in
            do {
                dbPool = try openReadOnlyDatabase(at: url)
            } catch {
                dbError = error
            }
        }

        if let error = dbError ?? coordinatorError {
            throw error
        }

        return dbPool
    }

    private func openReadOnlyDatabase(at databaseURL: URL) throws -> DatabasePool? {
        do {
            var configuration = Configuration()
            configuration.readonly = true
            return try DatabasePool(path: databaseURL.path, configuration: configuration)
        } catch {
            if FileManager.default.fileExists(atPath: databaseURL.path) {
                throw error
            }

            return nil
        }
    }

    private func connectDB() throws -> DatabasePool? {
        let dbURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetConstants.appGroupIdentifier)!
            .appendingPathComponent(WidgetConstants.databaseName)
        return try openSharedReadOnlyDatabase(at: dbURL)
    }

    private func selectedColleges() -> CollegeSelection {
        var collegeId = UserDefaults.shared.integer(forKey: "collegeId")
        let showBothCollege = UserDefaults.shared.bool(forKey: "showBothCollege")

        if collegeId == 0 {
            collegeId = WidgetConstants.defaultCollegeId
        }

        let college = College(rawValue: collegeId)!
        let colleges = (showBothCollege && college == .sjtu) ? [College.sjtu, .sjtug] : [college]

        return CollegeSelection(primaryCollege: college, colleges: colleges)
    }

    private func getSemester(pool: DatabasePool, college: College, date: Date) throws -> Semester? {
        try pool.read { db in
            try Semester
                .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
                .fetchOne(db)
        }
    }

    private func getSchedules(pool: DatabasePool, colleges: [College], date: Date) throws -> [ScheduleInfo] {
        var schedules: [ScheduleInfo] = []

        for college in colleges {
            guard let semester = try getSemester(pool: pool, college: college, date: date) else {
                return []
            }

            let week = date.weeksSince(semester.start_at)

            // TODO: College.custom
            let request = Schedule
                .including(required: Schedule.class_
                    .including(required: Class.course)
                    .filter(Column("semester_id") == semester.id)
                )
                .filter(
                    Column("week") == week &&
                    Column("is_start") == true &&
                    Column("college") == college &&
                    Column("day") == (date.get(.weekday) + 5) % 7
                )
                .order(Column("period"))

            schedules.append(contentsOf: try pool.read { db in
                try ScheduleInfo.fetchAll(db, request)
            })
        }

        return schedules.sorted { lhs, rhs in
            lhs.schedule.period < rhs.schedule.period
        }
    }

    private func getCustomSchedules(pool: DatabasePool, colleges: [College], date: Date) throws -> [CustomSchedule] {
        try pool.read { db in
            try CustomSchedule
                .filter(
                    colleges.contains(Column("college")) &&
                    Column("begin") >= date.startOfDay() &&
                    Column("begin") < date.addDays(1).startOfDay()
                )
                .fetchAll(db)
        }
    }

    private func loadScheduleData(at date: Date) throws -> LoadedScheduleData? {
        let collegeSelection = selectedColleges()

        guard let dbPool = try connectDB() else {
            return nil
        }

        return LoadedScheduleData(
            semester: try getSemester(pool: dbPool, college: collegeSelection.primaryCollege, date: date),
            courseSchedules: try getSchedules(pool: dbPool, colleges: collegeSelection.colleges, date: date),
            customSchedules: try getCustomSchedules(pool: dbPool, colleges: collegeSelection.colleges, date: date)
        )
    }

    private func makeWidgetSchedule(from schedule: ScheduleInfo) -> WidgetSchedule {
        WidgetSchedule(
            start: schedule.schedule.startTime(),
            end: schedule.schedule.finishTime(),
            name: schedule.course.name,
            location: schedule.schedule.classroom,
            color: schedule.class_.color
        )
    }

    private func makeWidgetSchedule(from schedule: CustomSchedule) -> WidgetSchedule {
        WidgetSchedule(
            start: schedule.begin.formatted(format: WidgetConstants.timeFormat),
            end: schedule.end.formatted(format: WidgetConstants.timeFormat),
            name: schedule.name,
            location: schedule.location,
            color: schedule.color
        )
    }

    private func buildWidgetSchedules(
        courseSchedules: [ScheduleInfo],
        customSchedules: [CustomSchedule],
        at date: Date,
        includeFinished: Bool
    ) -> [WidgetSchedule] {
        let courseWidgetSchedules = courseSchedules
            .map { makeWidgetSchedule(from: $0) }
            .filter { includeFinished || $0.endDate(on: date) > date }

        let customWidgetSchedules = customSchedules
            .filter { includeFinished || $0.end > date }
            .map { makeWidgetSchedule(from: $0) }

        return (courseWidgetSchedules + customWidgetSchedules)
            .sorted(by: { $0.isBefore($1) })
    }

    private func makeStatus(courseSchedulesCount: Int, widgetSchedulesCount: Int) -> DailyStatus {
        if courseSchedulesCount == 0 {
            return .noSchedules
        }

        if widgetSchedulesCount == 0 {
            return .allSchedulesFinished
        }

        return .hasSchedules
    }

    private func makeSnapshotEntry(from data: LoadedScheduleData, at date: Date) -> ScheduleEntry {
        let widgetSchedules = buildWidgetSchedules(
            courseSchedules: data.courseSchedules,
            customSchedules: data.customSchedules,
            at: date,
            includeFinished: false
        )

        return ScheduleEntry(
            date: date,
            schedules: widgetSchedules,
            semester: data.semester,
            status: makeStatus(
                courseSchedulesCount: data.courseSchedules.count,
                widgetSchedulesCount: widgetSchedules.count
            )
        )
    }

    private func makeTimeline(from data: LoadedScheduleData, at currentDate: Date) -> Timeline<ScheduleEntry> {
        let widgetSchedules = buildWidgetSchedules(
            courseSchedules: data.courseSchedules,
            customSchedules: data.customSchedules,
            at: currentDate,
            includeFinished: true
        )

        guard !widgetSchedules.isEmpty else {
            return Timeline(
                entries: [
                    ScheduleEntry(
                        date: currentDate,
                        schedules: [],
                        semester: data.semester,
                        status: .noSchedules
                    )
                ],
                policy: .after(currentDate.addHours(1))
            )
        }

        var entries: [ScheduleEntry] = []

        for (index, schedule) in widgetSchedules.enumerated() {
            if schedule.endDate(on: currentDate) < currentDate {
                continue
            }

            let startDate = schedule.startDate(on: currentDate)
            let entryDate = index == 0
                ? currentDate
                : widgetSchedules[index - 1].endDate(on: currentDate)
            let remainingSchedules = Array(widgetSchedules[index...])

            entries.append(
                ScheduleEntry(
                    date: entryDate,
                    schedules: remainingSchedules,
                    semester: data.semester,
                    status: .hasSchedules
                )
            )
            entries.append(
                ScheduleEntry(
                    date: startDate,
                    schedules: remainingSchedules,
                    semester: data.semester,
                    status: .hasSchedules
                )
            )
        }

        entries.append(
            ScheduleEntry(
                date: widgetSchedules.last!.endDate(on: currentDate),
                schedules: [],
                semester: data.semester,
                status: .allSchedulesFinished
            )
        )

        return Timeline(entries: entries, policy: .after(currentDate.addDays(1).startOfDay()))
    }

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), schedules: nil, semester: nil, status: .loading)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let currentDate = Date()

        do {
            guard let data = try loadScheduleData(at: currentDate) else {
                return
            }

            completion(makeSnapshotEntry(from: data, at: currentDate))
        } catch {
            completion(ScheduleEntry(date: Date(), schedules: [], semester: nil, status: .noSchedules))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let currentDate = Date()

        do {
            guard let data = try loadScheduleData(at: currentDate) else {
                return
            }

            completion(makeTimeline(from: data, at: currentDate))
        } catch {
        }
    }
}

// MARK: - Shared Views

private struct ScheduleColorMark: View {
    let color: String

    var body: some View {
        RoundedRectangle(cornerRadius: WidgetLayout.colorMarkCornerRadius, style: .continuous)
            .fill(Color(hex: color))
            .frame(width: WidgetLayout.colorMarkSize, height: WidgetLayout.colorMarkSize)
    }
}

private struct PlaceholderScheduleText: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text(WidgetCopy.placeholderTitle)
            Text(WidgetCopy.placeholderSubtitle)
        }
        .redacted(reason: .placeholder)
    }
}

private extension WidgetFamily {
    var backgroundSlot: WidgetBackgroundSlot? {
        switch self {
        case .systemSmall:
            return .systemSmall
        case .systemMedium:
            return .systemMedium
        case .systemLarge:
            return .systemLarge
        default:
            return nil
        }
    }

    var hasCustomBackgroundImage: Bool {
        guard let slot = backgroundSlot,
              let filename = UserDefaults.shared.string(forKey: slot.storageKey),
              let imageURL = SharedContainerDirectory.widgetBackgroundURL(for: filename)
        else {
            return false
        }

        return FileManager.default.fileExists(atPath: imageURL.path)
    }
}

private struct HomeScreenWidgetBackground: View {
    let family: WidgetFamily

    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    private var systemBackgroundColor: Color {
        Color(UIColor.systemBackground)
    }

    private var backgroundSlot: WidgetBackgroundSlot? {
        family.backgroundSlot
    }

    private var customBackgroundImage: UIImage? {
        guard widgetRenderingMode == .fullColor,
              showsWidgetContainerBackground,
              let slot = backgroundSlot,
              let filename = UserDefaults.shared.string(forKey: slot.storageKey),
              let imageURL = SharedContainerDirectory.widgetBackgroundURL(for: filename)
        else {
            return nil
        }

        return UIImage(contentsOfFile: imageURL.path)
    }

    private var backgroundEffect: WidgetBackgroundEffectConfiguration {
        guard let backgroundSlot else {
            return .defaultValue
        }

        return .init(
            transparency: UserDefaults.shared.object(forKey: backgroundSlot.transparencyKey) as? Double
                ?? WidgetBackgroundEffectConfiguration.defaultTransparency,
            blurRadius: UserDefaults.shared.object(forKey: backgroundSlot.blurRadiusKey) as? Double
                ?? WidgetBackgroundEffectConfiguration.defaultBlurRadius
        )
    }

    var body: some View {
        if let customBackgroundImage {
            Image(uiImage: customBackgroundImage)
                .resizable()
                .scaledToFill()
                .opacity(backgroundEffect.imageOpacity)
                .blur(radius: backgroundEffect.clampedBlurRadius)
                .scaleEffect(WidgetBackgroundLayout.imageScale)
                .overlay {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    systemBackgroundColor.opacity(backgroundEffect.topOverlayOpacity),
                                    systemBackgroundColor.opacity(backgroundEffect.middleOverlayOpacity),
                                    systemBackgroundColor.opacity(backgroundEffect.bottomOverlayOpacity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Rectangle()
                        .fill(systemBackgroundColor.opacity(backgroundEffect.flatOverlayOpacity))
                }
        } else {
            systemBackgroundColor
        }
    }
}

private struct WidgetCardBackground: View {
    let accentColor: String?
    let emphasized: Bool
    let contrastStyle: WidgetCardSurfaceContrastStyle

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WidgetLayout.cardCornerRadius, style: .continuous)
    }

    private var usesElevatedContrast: Bool {
        contrastStyle == .elevated && colorScheme == .light
    }

    private var topFillOpacity: Double {
        if usesElevatedContrast {
            return emphasized ? 0.82 : 0.76
        }

        switch colorScheme {
        case .dark:
            return emphasized ? 0.18 : 0.12
        case .light:
            return emphasized ? 0.22 : 0.16
        @unknown default:
            return emphasized ? 0.22 : 0.16
        }
    }

    private var bottomFillOpacity: Double {
        if usesElevatedContrast {
            return emphasized ? 0.64 : 0.56
        }

        switch colorScheme {
        case .dark:
            return emphasized ? 0.08 : 0.05
        case .light:
            return emphasized ? 0.11 : 0.07
        @unknown default:
            return emphasized ? 0.11 : 0.07
        }
    }

    private var borderTopOpacity: Double {
        if usesElevatedContrast {
            return emphasized ? 0.58 : 0.46
        }

        switch colorScheme {
        case .dark:
            return emphasized ? 0.26 : 0.18
        case .light:
            return emphasized ? 0.34 : 0.24
        @unknown default:
            return emphasized ? 0.34 : 0.24
        }
    }

    private var borderBottomOpacity: Double {
        if usesElevatedContrast {
            return emphasized ? 0.28 : 0.18
        }

        switch colorScheme {
        case .dark:
            return emphasized ? 0.10 : 0.06
        case .light:
            return emphasized ? 0.16 : 0.10
        @unknown default:
            return emphasized ? 0.16 : 0.10
        }
    }

    private var shadowOpacity: Double {
        if usesElevatedContrast {
            return 0.16
        }

        return colorScheme == .dark ? 0.22 : 0.08
    }

    private var highlightBorderOpacity: Double {
        if usesElevatedContrast {
            return 0.34
        }

        switch colorScheme {
        case .dark:
            return 0.52
        case .light:
            return 0.38
        @unknown default:
            return 0.38
        }
    }

    private var accentTopOpacity: Double {
        usesElevatedContrast ? 0.98 : 0.95
    }

    private var accentBottomOpacity: Double {
        usesElevatedContrast ? 0.42 : 0.35
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(topFillOpacity),
                        Color.white.opacity(bottomFillOpacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderTopOpacity),
                                Color.white.opacity(borderBottomOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: WidgetCardSurfaceLayout.borderWidth
                    )
            }
            .overlay {
                if emphasized, let accentColor {
                    shape
                        .strokeBorder(
                            Color(hex: accentColor, opacity: highlightBorderOpacity),
                            lineWidth: WidgetCardSurfaceLayout.highlightBorderWidth
                        )
                }
            }
            .overlay(alignment: .leading) {
                if emphasized, let accentColor {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: accentColor, opacity: accentTopOpacity),
                                    Color(hex: accentColor, opacity: accentBottomOpacity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: WidgetCardSurfaceLayout.accentWidth, height: WidgetCardSurfaceLayout.accentHeight)
                        .padding(.leading, WidgetCardSurfaceLayout.accentInset)
                        .padding(.vertical, WidgetCardSurfaceLayout.accentVerticalInset)
                }
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: WidgetCardSurfaceLayout.shadowRadius, y: WidgetCardSurfaceLayout.shadowYOffset)
    }
}

private struct ScheduleListDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    private var lineOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.28
    }

    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.02),
                Color.white.opacity(lineOpacity),
                Color.white.opacity(0.02)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.vertical, WidgetScheduleListLayout.dividerVerticalPadding)
    }
}

private struct ScheduleRowView: View {
    let date: Date
    let schedule: WidgetSchedule

    @Environment(\.widgetFamily) private var widgetFamily

    private var usesCompactTimeLabel: Bool {
        switch widgetFamily {
        case .systemSmall:
            return true
        default:
            return false
        }
    }

    private var timeLabel: String {
        let startLabel = schedule.startLabel(at: date)
        return usesCompactTimeLabel ? startLabel : "\(startLabel) - \(schedule.end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetScheduleListLayout.rowSpacing) {
            scheduleHeader
            scheduleTitle
        }
        .frame(maxWidth: .infinity)
    }

    private var scheduleHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeLabel)
                .fontWeight(.bold)
                .font(.footnote)

            Spacer(minLength: 8)

            Text(schedule.location)
                .font(.caption)
                .foregroundStyle(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .fontDesign(.rounded)
    }

    private var scheduleTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let color = schedule.color {
                ScheduleColorMark(color: color)
            } else {
                Color.clear
                    .frame(width: WidgetLayout.colorMarkSize, height: WidgetLayout.colorMarkSize)
            }

            Text(schedule.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(2)
        }
    }
}

// MARK: - Entry View

struct MySJTUWidgetEntryView: View {
    var entry: Provider.Entry

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var visibleScheduleLimit: Int {
        widgetFamily == .systemLarge ? 4 : 1
    }

    private var cardSurfaceContrastStyle: WidgetCardSurfaceContrastStyle {
        if colorScheme == .light && !widgetFamily.hasCustomBackgroundImage {
            return .elevated
        }

        return .standard
    }

    private var accessoryInlineText: String? {
        if let schedule = entry.firstSchedule {
            return schedule.isCurrent(at: entry.date) ? schedule.name : "\(schedule.start) \(schedule.name)"
        }

        if entry.schedules != nil {
            return entry.emptyStateText
        }

        return nil
    }

    var body: some View {
        switch widgetFamily {
        case .accessoryInline:
            accessoryInlineView
        case .accessoryRectangular:
            accessoryRectangularView
        default:
            standardWidgetView
        }
    }

    @ViewBuilder
    private var accessoryInlineView: some View {
        if let accessoryInlineText {
            Text(accessoryInlineText)
                .fontWeight(.bold)
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var accessoryRectangularView: some View {
        VStack(spacing: 2) {
            if let schedule = entry.firstSchedule {
                accessoryRectangularScheduleView(for: schedule)
            } else if entry.schedules != nil {
                VStack(spacing: 8) {
                    Text("🎉")
                    Text(entry.emptyStateText)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
            } else {
                PlaceholderScheduleText()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.clear, for: .widget)
    }

    private var standardWidgetView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                headerView

                VStack(spacing: 2) {
                    standardWidgetContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer().frame(width: 0)
        }
        .padding(6)
        .containerBackground(for: .widget) {
            HomeScreenWidgetBackground(family: widgetFamily)
        }
    }

    @ViewBuilder
    private var standardWidgetContent: some View {
        if let schedules = entry.schedules {
            if schedules.isEmpty {
                emptyStateCard
            } else {
                schedulesCard(for: schedules)
            }
        } else {
            placeholderCard
        }
    }

    private func accessoryRectangularScheduleView(for schedule: WidgetSchedule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(schedule.startLabel(at: entry.date))
                    .fontWeight(.bold)
                    .font(.footnote)
                Spacer()
                Text(schedule.location)
                    .font(.footnote)
            }
            .fontDesign(.rounded)

            HStack(alignment: .firstTextBaseline) {
                if let color = schedule.color {
                    ScheduleColorMark(color: color)
                }

                Text(schedule.name)
                    .fontWeight(.bold)
            }
        }
        .padding(10)
    }

    private var headerView: some View {
        HStack {
            Text("\(entry.date.get(.day))")
                .font(.largeTitle)
                .fontWeight(.medium)
                .fontDesign(.rounded)

            if let semester = entry.semester {
                VStack(alignment: .leading) {
                    Text(semesterTitle(for: semester))
                        .font(.caption2)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                    Text(semesterWeekTitle(for: semester))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
            }
        }
        .padding([.top, .leading, .trailing], 10)
    }

    @ViewBuilder
    private func schedulesCard(for schedules: [WidgetSchedule]) -> some View {
        let visibleSchedules = Array(schedules.prefix(visibleScheduleLimit))
        let hiddenCount = max(schedules.count - visibleScheduleLimit, 0)
        let nextHiddenSchedule = hiddenCount > 0 ? schedules[visibleScheduleLimit] : nil
        let highlightedSchedule = visibleSchedules.first(where: { $0.isCurrent(at: entry.date) })

        cardContainer(
            accentColor: highlightedSchedule?.color,
            emphasized: highlightedSchedule != nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleSchedules.enumerated()), id: \.offset) { index, schedule in
                    if index > 0 {
                        ScheduleListDivider()
                    }

                    ScheduleRowView(date: entry.date, schedule: schedule)
                }

                if let nextHiddenSchedule {
                    ScheduleListDivider()
                    overflowIndicatorView(hiddenCount: hiddenCount, nextSchedule: nextHiddenSchedule)
                }
            }
            .padding(WidgetScheduleListLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func overflowIndicatorView(hiddenCount: Int, nextSchedule: WidgetSchedule) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(nextSchedule.start)
                .fontWeight(.bold)
                .font(.footnote)
                .fontDesign(.rounded)

            if widgetFamily != .systemSmall {
                Text("后续还有 \(hiddenCount) 节")
                    .font(.caption)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("···")
                .font(.caption)
                .foregroundStyle(Color(UIColor.secondaryLabel))
        }
    }

    private var emptyStateCard: some View {
        cardContainer(
            alignment: .center,
            expandsToAvailableHeight: true,
            expandedTopInset: 6
        ) {
            VStack(spacing: 8) {
                Text("🎉")
                Text(entry.emptyStateText)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .multilineTextAlignment(.center)
            .padding(WidgetScheduleListLayout.cardPadding)
        }
    }

    private var placeholderCard: some View {
        cardContainer {
            PlaceholderScheduleText()
                .padding(WidgetScheduleListLayout.cardPadding)
        }
    }

    private func cardContainer<Content: View>(
        accentColor: String? = nil,
        emphasized: Bool = false,
        alignment: Alignment = .leading,
        expandsToAvailableHeight: Bool = false,
        expandedTopInset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if expandsToAvailableHeight {
                VStack(spacing: 0) {
                    content()
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .padding(.top, expandedTopInset)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    WidgetCardBackground(
                        accentColor: accentColor,
                        emphasized: emphasized,
                        contrastStyle: cardSurfaceContrastStyle
                    )
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    content()
                        .frame(maxWidth: .infinity, alignment: alignment)
                }
                .background {
                    WidgetCardBackground(
                        accentColor: accentColor,
                        emphasized: emphasized,
                        contrastStyle: cardSurfaceContrastStyle
                    )
                }
            }
        }
    }

    private func semesterTitle(for semester: Semester) -> String {
        "\(String(semester.year))\(["秋", "春", "夏"][semester.semester - 1])季学期"
    }

    private func semesterWeekTitle(for semester: Semester) -> String {
        "第\(entry.date.weeksSince(semester.start_at) + 1)周・\(entry.date.localeWeekday())"
    }
}

struct MySJTUWidget: Widget {
    let kind: String = "MySJTUWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(macOS 14.0, iOS 17.0, *) {
                MySJTUWidgetEntryView(entry: entry)
            } else {
                MySJTUWidgetEntryView(entry: entry)
                    .background()
            }
        }
        .configurationDisplayName("今日日程")
        .description("今天要上的课喵")
        .contentMarginsDisabled()
#if os(watchOS)
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
#else
        .supportedFamilies([.accessoryRectangular, .accessoryInline,
                            .systemSmall, .systemMedium, .systemLarge])
#endif
    }
}

#Preview(as: .systemSmall) {
    MySJTUWidget()
} timeline: {
    ScheduleEntry(date: .now, schedules: nil, semester: nil, status: .loading)
    ScheduleEntry(date: .now, schedules: [], semester: nil, status: .noSchedules)
    ScheduleEntry(date: .now, schedules: [], semester: nil, status: .allSchedulesFinished)
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "8:00", end: "9:40", name: "高等数学", location: "上院 105", color: "#66ccff")
        ],
        semester: Semester(id: "", college: .sjtu, year: 2024, semester: 1, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2024-09-12")!, end_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2025-01-30")!),
        status: .hasSchedules
    )
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "14:00", end: "15:40", name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: "#66ccff")
        ],
        semester: Semester(id: "", college: .sjtu, year: 2024, semester: 1, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2024-09-12")!, end_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2025-01-30")!),
        status: .hasSchedules
    )
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "14:00", end: "15:40", name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: nil),
            WidgetSchedule(start: "20:00", end: "21:40", name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: nil)
        ],
        semester: Semester(id: "", college: .sjtu, year: 2024, semester: 1, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2024-09-12")!, end_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2025-01-30")!),
        status: .hasSchedules
    )
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "8:00", end: "9:40", name: "高等数学", location: "上院 105", color: nil),
            WidgetSchedule(start: "14:00", end: "15:40", name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: nil)
        ],
        semester: nil,
        status: .hasSchedules
    )
}
