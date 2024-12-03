//
//  MySJTUWidget.swift
//  MySJTUWidget
//
//  Created by boar on 2024/11/25.
//

import WidgetKit
import SwiftUI
import GRDB
import SQLite3

struct WidgetSchedule: Hashable {
    let start: String
    let end: String
    let length: Int
    let name: String
    let location: String
    let color: String?
}

struct Provider: TimelineProvider {
    /// Returns an initialized database pool at the shared location databaseURL,
    /// or nil if the database is not created yet, or does not have the required
    /// schema version.
    func openSharedReadOnlyDatabase(at databaseURL: URL) throws -> DatabasePool? {
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
            let dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)
            return dbPool
        } catch {
            if FileManager.default.fileExists(atPath: databaseURL.path) {
                throw error
            } else {
                return nil
            }
        }
    }
    
    func connectDB() throws -> DatabasePool? {
        let dbURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.boar.sjct")!
            .appendingPathComponent("class_table.db")
        return try openSharedReadOnlyDatabase(at: dbURL)
    }
    
    func getSemester(pool: DatabasePool, college: College, date: Date) throws -> Semester? {
        return try pool.read { db in
            try Semester
                .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
                .fetchOne(db)
        }
    }
    
    func getSchedules(pool: DatabasePool, college: College, date: Date) throws -> [ScheduleInfo] {
        let semester = try pool.read { db in
            try Semester
                .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
                .fetchOne(db)
        }
        
        guard let semester = semester else {
            return []
        }
        let week = date.weeksSince(semester.start_at)
        
        let request = Schedule
            .including(required: Schedule.class_
                .including(required: Class.course)
                .filter(Column("semester_id") == semester.id)
            )
            .filter(
                Column("week") == week &&
                Column("is_start") == true &&
                [College.custom, college].contains(Column("college")) &&
                Column("day") == (date.get(.weekday) + 5) % 7
            )
            .order(Column("period"))
        
        return try pool.read { db in
            try ScheduleInfo.fetchAll(db, request)
        }
    }

    func placeholder(in context: Context) -> ScheduleEntry {
        return ScheduleEntry(date: Date(), schedules: nil, semester: nil, status: .loading)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> ()) {
        let currentDate = Date()
        var collegeId = UserDefaults.shared.integer(forKey: "collegeId")
        if collegeId == 0 {
            collegeId = 1
        }
        let college = College(rawValue: collegeId)!

        do {
            if let db = try connectDB() {
                let semester = try getSemester(pool: db, college: college, date: currentDate)
                let schedules = try getSchedules(pool: db, college: college, date: currentDate)
                            
                // Generate a timeline consisting of five entries an hour apart, starting from the current date.
                var widgetSchedules: [WidgetSchedule] = []
                for schedule in schedules {
                    let finishDate = currentDate.timeOfDay("H:mm", timeStr: schedule.schedule.finishTime())!
                    
                    if finishDate > currentDate {
                        widgetSchedules.append(
                            WidgetSchedule(
                                start: schedule.schedule.startTime(),
                                end: schedule.schedule.finishTime(),
                                length: schedule.schedule.length,
                                name: schedule.course.name,
                                location: schedule.schedule.classroom,
                                color: schedule.class_.color
                            )
                        )
                    }
                }
                
                var status: DailyStatus = .hasSchedules
                if schedules.count == 0 {
                    status = .noSchedules
                } else if widgetSchedules.count == 0 {
                    status = .allSchedulesFinished
                }
                
                let entry = ScheduleEntry(date: currentDate, schedules: widgetSchedules, semester: semester, status: status)
                completion(entry)
            }
        } catch {
            let entry = ScheduleEntry(date: Date(), schedules: [], semester: nil, status: .noSchedules)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        var collegeId = UserDefaults.shared.integer(forKey: "collegeId")
        if collegeId == 0 {
            collegeId = 1
        }
        let college = College(rawValue: collegeId)!
        
        do {
            if let db = try connectDB() {
                let semester = try getSemester(pool: db, college: college, date: currentDate)
                let schedules = try getSchedules(pool: db, college: college, date: currentDate)
                
                var entries: [ScheduleEntry] = []
                
                // Generate a timeline consisting of five entries an hour apart, starting from the current date.
                if schedules.count > 0 {
                    for (index, schedule) in schedules.enumerated() {
                        if currentDate.timeOfDay("H:mm", timeStr: schedule.schedule.finishTime())! < currentDate {
                            continue
                        }
                        
                        // let entryDate = currentDate.timeOfDay("H:mm", timeStr: schedule.schedule.startTime())!
                        let startDate = currentDate.timeOfDay("H:mm", timeStr: schedule.schedule.startTime())!
                        let entryDate = index == 0 ? currentDate : currentDate.timeOfDay("H:mm", timeStr: schedules[index - 1].schedule.finishTime())!
                        var widgetSchedules: [WidgetSchedule] = []
                        
                        for i in index..<schedules.count {
                            let schedule = schedules[i]
                            
                            widgetSchedules.append(
                                WidgetSchedule(
                                    start: schedule.schedule.startTime(),
                                    end: schedule.schedule.finishTime(),
                                    length: schedule.schedule.length,
                                    name: "\(schedule.course.name)",
                                    location: schedule.schedule.classroom,
                                    color: schedule.class_.color
                                )
                            )
                        }
                        
                        entries.append(
                            ScheduleEntry(date: entryDate, schedules: widgetSchedules, semester: semester, status: widgetSchedules.count > 0 ? .hasSchedules : .allSchedulesFinished)
                        )
                        entries.append(
                            ScheduleEntry(date: startDate, schedules: widgetSchedules, semester: semester, status: widgetSchedules.count > 0 ? .hasSchedules : .allSchedulesFinished)
                        )
                    }
                    
                    entries.append(ScheduleEntry(date: currentDate.timeOfDay("H:mm", timeStr: schedules.last!.schedule.finishTime())!, schedules: [], semester: semester, status: .allSchedulesFinished))

                    let timeline = Timeline(entries: entries, policy: .after(currentDate.addDays(1).startOfDay()))
                    completion(timeline)
                } else {
                    let timeline = Timeline(
                        entries: [ScheduleEntry(date: currentDate, schedules: [], semester: semester, status: .noSchedules)],
                        policy: .after(currentDate.addHours(1))
                    )
                    completion(timeline)
                }
            }
        } catch {
        }
    }

//    func relevances() async -> WidgetRelevances<Void> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
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

struct ScheduleView : View {
    let date: Date
    let schedule: WidgetSchedule
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let startDate = date.timeOfDay("H:mm", timeStr: schedule.start)!
        
        VStack(alignment: .leading) {
            HStack {
                if widgetFamily == .systemSmall ||
                    widgetFamily == .accessoryCircular ||
                    widgetFamily == .accessoryInline ||
                    widgetFamily == .accessoryRectangular {
                    Text(startDate > date ? schedule.start : "当前")
                        .fontWeight(.bold)
                        .font(.footnote)
                } else {
                    Text("\(startDate > date ? schedule.start : "当前") - \(schedule.end)")
                        .fontWeight(.bold)
                        .font(.footnote)
                }
                Spacer()
                Text(schedule.location)
                    .font(.caption)
            }
            .fontDesign(.rounded)
            Spacer().frame(height: 4)
            HStack(alignment: .firstTextBaseline) {
                if let color = schedule.color {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(hex: color))
                        .frame(width: 10, height: 10)
                }
                Text(schedule.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background {
            if widgetFamily == .accessoryRectangular {
                Color.clear
            } else if startDate > date {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThickMaterial)
            } else if let color = schedule.color {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: color, opacity: 0.6), lineWidth: 2)
                    .fill(.ultraThickMaterial)
            }
        }
    }
}

struct MySJTUWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        if widgetFamily == .accessoryInline {
            HStack {
                if let schedules = entry.schedules {
                    if schedules.count > 0 {
                        if let schedule = schedules.first {
                            let startDate = entry.date.timeOfDay("H:mm", timeStr: schedule.start)!
                            
                            Text(
                                startDate > entry.date ?
                                "\(schedule.start) \(schedule.name)"
                                :
                                    schedule.name
                            )
                            .fontWeight(.bold)
                            .font(.footnote)
                        }
                    } else {
                        Text(entry.status == .noSchedules ? "今天没有课程" : "已上完全部课程")
                            .fontWeight(.bold)
                            .font(.footnote)
                    }
                }
            }
        } else if widgetFamily == .accessoryRectangular {
            VStack(spacing: 2) {
                if let schedules = entry.schedules {
                    if schedules.count > 0 {
                        if let schedule = schedules.first {
                            let startDate = entry.date.timeOfDay("H:mm", timeStr: schedule.start)!
                            
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(startDate > entry.date ? schedule.start : "当前")
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
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(Color(hex: color))
                                            .frame(width: 10, height: 10)
                                    }
                                    Text(schedule.name)
                                        .fontWeight(.bold)
                                }
                            }
                            .padding(10)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("🎉")
                            Text(entry.status == .noSchedules ? "今天没有课程" : "已上完全部课程")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("这个文本框是课程名称的占位符")
                            .redacted(reason: .placeholder)
                        Text("这里是地点")
                            .redacted(reason: .placeholder)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(entry.date.get(.day))")
                            .font(.largeTitle)
                            .fontWeight(.medium)
                            .fontDesign(.rounded)
                        
                        if let semester = entry.semester {
                            VStack(alignment: .leading) {
                                Text("\(String(semester.year))\(["秋", "春", "夏"][semester.semester - 1])季学期")
                                    .font(.caption2)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                                Text("第\(entry.date.weeksSince(semester.start_at) + 1)周・\(entry.date.localeWeekday())")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                    .padding([.top, .leading, .trailing], 10)
                                                    
                    VStack(spacing: 2) {
                        if let schedules = entry.schedules {
                            if schedules.count > 0 {
                                Spacer()
                                
                                if widgetFamily == .systemLarge {
                                    ForEach(schedules.prefix(4), id: \.self) { schedule in
                                        ScheduleView(date: entry.date, schedule: schedule)
                                    }
                                } else {
                                    if let schedule = schedules.first {
                                        ScheduleView(date: entry.date, schedule: schedule)
                                    }
                                }
                                
                                if schedules.count > (widgetFamily == .systemLarge ? 4 : 1) {
                                    let schedule = schedules[1]
                                    
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
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(.ultraThickMaterial)
                                    }
                                }

                            } else {
                                Spacer()
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.ultraThickMaterial)
                                    .overlay {
                                        VStack(spacing: 8) {
                                            Text("🎉")
                                            Text(entry.status == .noSchedules ? "今天没有课程" : "已上完全部课程")
                                                .font(.callout)
                                                .fontWeight(.medium)
                                        }
                                        .padding([.leading, .trailing], 8)
                                        .frame(maxWidth: .infinity)
                                    }
                            }
                        } else {
                            Spacer()
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThickMaterial)
                                .overlay {
                                    VStack(alignment: .leading) {
                                        Text("这个文本框是课程名称的占位符")
                                            .redacted(reason: .placeholder)
                                        Text("这里是地点")
                                            .redacted(reason: .placeholder)
                                    }
                                    .padding([.leading, .trailing], 8)
                                    .frame(maxWidth: .infinity)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Spacer().frame(width: 0)
            }
            .padding(6)
        }
    }
}

struct MySJTUWidget: Widget {
    let kind: String = "MySJTUWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(macOS 14.0, iOS 17.0, *) {
                MySJTUWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                MySJTUWidgetEntryView(entry: entry)
                // .padding()
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
