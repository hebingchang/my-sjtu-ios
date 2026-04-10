//
//  WatchScheduleSync.swift
//  MySJTU
//
//  Created by boar on 2026/03/27.
//

import Foundation

struct WatchScheduleSnapshot: Codable {
    let generatedAt: Date
    let sourceName: String
    let days: [WatchScheduleDaySnapshot]
}

struct WatchScheduleDaySnapshot: Codable {
    let date: Date
    let items: [WatchScheduleItemSnapshot]
}

struct WatchScheduleItemSnapshot: Codable {
    let id: String
    let kind: WatchScheduleItemKind
    let title: String
    let subtitle: String
    let startAt: Date
    let endAt: Date
    let colorHex: String
}

enum WatchScheduleItemKind: String, Codable {
    case course
    case custom
}

enum WatchScheduleSyncPayload {
    static let snapshotKey = "watch.schedule.snapshot"
    static let refreshCommand = "watch.schedule.refresh"
}

enum WatchScheduleSnapshotBuilder {
    private static let dayRangeLength = 14

    static func makePayloadData(referenceDate: Date = .now) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(makeSnapshot(referenceDate: referenceDate))
    }

    static func makeSnapshot(referenceDate: Date = .now) throws -> WatchScheduleSnapshot {
        let colleges = AcademicContextService.selectedColleges()
        let rangeStart = referenceDate.startOfWeek()
        let dates = (0..<dayRangeLength).map { rangeStart.addDays($0) }

        guard let pool = Eloquent.pool else {
            throw EloquentError.dbNotOpened
        }

        let includeSourcePrefix = colleges.count > 1

        let days = try pool.read { db in
            try dates.map { date in
                let schedules = try SchedulesRequest(colleges: colleges, date: date).fetch(db)
                let customSchedules = try CustomSchedulesRequest(colleges: colleges, date: date).fetch(db)
                let items = scheduleItems(
                    from: schedules,
                    on: date,
                    includeSourcePrefix: includeSourcePrefix
                ) + customScheduleItems(
                    from: customSchedules,
                    includeSourcePrefix: includeSourcePrefix
                )

                return WatchScheduleDaySnapshot(
                    date: date.startOfDay(),
                    items: items.sorted(by: itemSort)
                )
            }
        }

        return WatchScheduleSnapshot(
            generatedAt: .now,
            sourceName: AcademicContextService.selectedSourceName(),
            days: days
        )
    }

    private static func scheduleItems(
        from schedules: [ScheduleInfo],
        on date: Date,
        includeSourcePrefix: Bool
    ) -> [WatchScheduleItemSnapshot] {
        schedules.map { info in
            let location = info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom
            let prefix = includeSourcePrefix ? "\(AcademicContextService.shortName(for: info.class_.college)) · " : ""

            return WatchScheduleItemSnapshot(
                id: info.id,
                kind: .course,
                title: info.course.name,
                subtitle: prefix + location,
                startAt: date.timeOfDay("H:mm", timeStr: info.schedule.startTime()) ?? date,
                endAt: date.timeOfDay("H:mm", timeStr: info.schedule.finishTime()) ?? date,
                colorHex: info.class_.color
            )
        }
    }

    private static func customScheduleItems(
        from schedules: [CustomSchedule],
        includeSourcePrefix: Bool
    ) -> [WatchScheduleItemSnapshot] {
        schedules.map { schedule in
            let baseSubtitle = firstNonEmpty([
                schedule.location,
                schedule.description,
                "自定义日程"
            ])

            let prefix: String
            if includeSourcePrefix, let college = schedule.college {
                prefix = "\(AcademicContextService.shortName(for: college)) · "
            } else {
                prefix = ""
            }

            return WatchScheduleItemSnapshot(
                id: "custom-\(schedule.id ?? -1)-\(schedule.begin.timeIntervalSince1970)",
                kind: .custom,
                title: schedule.name,
                subtitle: prefix + baseSubtitle,
                startAt: schedule.begin,
                endAt: schedule.end,
                colorHex: schedule.color ?? "#5D737E"
            )
        }
    }

    private static func firstNonEmpty(_ values: [String]) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    private static func itemSort(lhs: WatchScheduleItemSnapshot, rhs: WatchScheduleItemSnapshot) -> Bool {
        if lhs.startAt != rhs.startAt {
            return lhs.startAt < rhs.startAt
        }

        if lhs.endAt != rhs.endAt {
            return lhs.endAt < rhs.endAt
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
