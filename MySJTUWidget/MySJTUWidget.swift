//
//  MySJTUWidget.swift
//  MySJTUWidget
//
//  Created by boar on 2024/11/25.
//

import WidgetKit
import SwiftUI
import GRDB

// MARK: - Constants

private enum WidgetConstants {
    static let timeFormat = "H:mm"
    static let defaultCollegeId = 1
    static let appGroupIdentifier = "group.com.boar.sjct"
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
    static let cardCornerRadius: CGFloat = 18
    static let colorMarkCornerRadius: CGFloat = 2
    static let colorMarkSize: CGFloat = 10
}

// MARK: - Models

struct WidgetSchedule: Hashable {
    let start: String
    let end: String
    let length: Int
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
}

enum DailyStatus {
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
        switch status {
        case .noSchedules:
            return WidgetCopy.noSchedules
        case .loading, .hasSchedules, .allSchedulesFinished:
            return WidgetCopy.allSchedulesFinished
        }
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
            length: schedule.schedule.length,
            name: schedule.course.name,
            location: schedule.schedule.classroom,
            color: schedule.class_.color
        )
    }

    private func makeWidgetSchedule(from schedule: CustomSchedule) -> WidgetSchedule {
        WidgetSchedule(
            start: schedule.begin.formatted(format: WidgetConstants.timeFormat),
            end: schedule.end.formatted(format: WidgetConstants.timeFormat),
            length: 0,
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
        var widgetSchedules = courseSchedules.compactMap { schedule in
            let widgetSchedule = makeWidgetSchedule(from: schedule)

            if includeFinished || widgetSchedule.endDate(on: date) > date {
                return widgetSchedule
            }

            return nil
        }

        widgetSchedules += customSchedules.compactMap { schedule in
            if includeFinished || schedule.end > date {
                return makeWidgetSchedule(from: schedule)
            }

            return nil
        }

        return widgetSchedules.sorted(by: { $0.isBefore($1) })
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
            let entrySchedules = Array(widgetSchedules[index...])
            let status: DailyStatus = entrySchedules.isEmpty ? .allSchedulesFinished : .hasSchedules

            entries.append(
                ScheduleEntry(
                    date: entryDate,
                    schedules: entrySchedules,
                    semester: data.semester,
                    status: status
                )
            )
            entries.append(
                ScheduleEntry(
                    date: startDate,
                    schedules: entrySchedules,
                    semester: data.semester,
                    status: status
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

//    func relevances() async -> WidgetRelevances<Void> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
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
                .redacted(reason: .placeholder)
            Text(WidgetCopy.placeholderSubtitle)
                .redacted(reason: .placeholder)
        }
    }
}

struct ScheduleView: View {
    let date: Date
    let schedule: WidgetSchedule

    @Environment(\.widgetFamily) private var widgetFamily

    private var startDate: Date {
        schedule.startDate(on: date)
    }

    private var startLabel: String {
        startDate > date ? schedule.start : WidgetCopy.current
    }

    private var usesCompactTimeLabel: Bool {
        switch widgetFamily {
        case .systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular:
            return true
        default:
            return false
        }
    }

    private var timeLabel: String {
        usesCompactTimeLabel ? startLabel : "\(startLabel) - \(schedule.end)"
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(timeLabel)
                    .fontWeight(.bold)
                    .font(.footnote)
                Spacer()
                Text(schedule.location)
                    .font(.caption)
            }
            .fontDesign(.rounded)

            Spacer().frame(height: 4)

            HStack(alignment: .firstTextBaseline) {
                if let color = schedule.color {
                    ScheduleColorMark(color: color)
                }

                Text(schedule.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background {
            cardBackground
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if widgetFamily == .accessoryRectangular {
            Color.clear
        } else if startDate > date {
            RoundedRectangle(cornerRadius: WidgetLayout.cardCornerRadius, style: .continuous)
                .fill(.ultraThickMaterial)
        } else if let color = schedule.color {
            RoundedRectangle(cornerRadius: WidgetLayout.cardCornerRadius, style: .continuous)
                .stroke(Color(hex: color, opacity: 0.6), lineWidth: 2)
                .fill(.ultraThickMaterial)
        }
    }
}

// MARK: - Entry View

struct MySJTUWidgetEntryView: View {
    var entry: Provider.Entry

    @Environment(\.widgetFamily) private var widgetFamily

    private var visibleScheduleLimit: Int {
        widgetFamily == .systemLarge ? 4 : 1
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
        HStack {
            if let schedule = entry.firstSchedule {
                let startDate = schedule.startDate(on: entry.date)

                Text(startDate > entry.date ? "\(schedule.start) \(schedule.name)" : schedule.name)
                    .fontWeight(.bold)
                    .font(.footnote)
            } else if entry.schedules != nil {
                Text(entry.emptyStateText)
                    .fontWeight(.bold)
                    .font(.footnote)
            }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer().frame(width: 0)
        }
        .padding(6)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func accessoryRectangularScheduleView(for schedule: WidgetSchedule) -> some View {
        let startDate = schedule.startDate(on: entry.date)

        VStack(alignment: .leading) {
            HStack {
                Text(startDate > entry.date ? schedule.start : WidgetCopy.current)
                    .fontWeight(.bold)
                    .font(.footnote)
                Spacer()
                Text(schedule.location)
                    .font(.footnote)
            }
            .fontDesign(.rounded)

            Spacer().frame(height: 4)

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
        Spacer()

        if widgetFamily == .systemLarge {
            ForEach(schedules.prefix(4), id: \.self) { schedule in
                ScheduleView(date: entry.date, schedule: schedule)
            }
        } else if let schedule = schedules.first {
            ScheduleView(date: entry.date, schedule: schedule)
        }

        if let overflowSchedule = overflowIndicatorSchedule(from: schedules) {
            overflowIndicatorView(for: overflowSchedule)
        }
    }

    private func overflowIndicatorSchedule(from schedules: [WidgetSchedule]) -> WidgetSchedule? {
        guard schedules.count > visibleScheduleLimit else {
            return nil
        }

        return schedules[1]
    }

    private func overflowIndicatorView(for schedule: WidgetSchedule) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(schedule.start)
                    .fontWeight(.bold)
                Spacer()
                Text("...")
            }
            .font(.footnote)
            .fontDesign(.rounded)
        }
        .padding([.leading, .trailing], 10)
        .padding([.top, .bottom], 6)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: WidgetLayout.cardCornerRadius, style: .continuous)
                .fill(.ultraThickMaterial)
        }
    }

    private var emptyStateCard: some View {
        Group {
            Spacer()
            RoundedRectangle(cornerRadius: WidgetLayout.cardCornerRadius, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay {
                    VStack(spacing: 8) {
                        Text("🎉")
                        Text(entry.emptyStateText)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .padding([.leading, .trailing], 8)
                    .frame(maxWidth: .infinity)
                }
        }
    }

    private var placeholderCard: some View {
        Group {
            Spacer()
            RoundedRectangle(cornerRadius: WidgetLayout.cardCornerRadius, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay {
                    PlaceholderScheduleText()
                        .padding([.leading, .trailing], 8)
                        .frame(maxWidth: .infinity)
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
                // .padding()
                    .background()
            }
        }
        .configurationDisplayName("今日日程")
        .description("今天要上的课喵")
        .containerBackgroundRemovable(false)
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
            WidgetSchedule(start: "8:00", end: "9:40", length: 2, name: "高等数学", location: "上院 105", color: "#66ccff")
        ],
        semester: Semester(id: "", college: .sjtu, year: 2024, semester: 1, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2024-09-12")!, end_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2025-01-30")!),
        status: .hasSchedules
    )
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "14:00", end: "15:40", length: 2, name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: "#66ccff")
        ],
        semester: Semester(id: "", college: .sjtu, year: 2024, semester: 1, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2024-09-12")!, end_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2025-01-30")!),
        status: .hasSchedules
    )
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "14:00", end: "15:40", length: 2, name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: nil),
            WidgetSchedule(start: "20:00", end: "21:40", length: 2, name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: nil)
        ],
        semester: Semester(id: "", college: .sjtu, year: 2024, semester: 1, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2024-09-12")!, end_at: Date.fromFormat("yyyy-MM-dd", dateStr: "2025-01-30")!),
        status: .hasSchedules
    )
    ScheduleEntry(
        date: .now,
        schedules: [
            WidgetSchedule(start: "8:00", end: "9:40", length: 2, name: "高等数学", location: "上院 105", color: nil),
            WidgetSchedule(start: "14:00", end: "15:40", length: 2, name: "毛泽东思想和中国特色社会主义理论体系概论", location: "东中院2-105", color: nil)
        ],
        semester: nil,
        status: .hasSchedules
    )
}
