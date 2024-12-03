//
//  Database.swift
//  MySJTU
//
//  Created by boar on 2024/11/05.
//

import Foundation
import GRDB
import GRDBQuery
import SQLite3

enum EloquentError: Error {
    case dbNotOpened
}

struct SchedulesRequest: ValueObservationQueryable {
    static var defaultValue: [ScheduleInfo] {
        []
    }
    var college: College?
    var date: Date?
    var isWeek: Bool = false

    func fetch(_ db: Database) throws -> [ScheduleInfo] {
        guard let college = college else {
            return []
        }
        guard let date = date else {
            return []
        }

        let semester = try Semester
            .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
            .fetchOne(db)
        guard let semester = semester else {
            return []
        }
        let week = date.weeksSince(semester.start_at)

        var filter = Column("week") == week && Column("is_start") == true && [College.custom, college].contains(Column("college"))
        if !isWeek {
            let day = (date.get(.weekday) + 5) % 7
            filter = filter && Column("day") == day
        }
        let request = Schedule
            .including(required: Schedule.class_
                .including(required: Class.course)
                .filter(Column("semester_id") == semester.id))
            .filter(filter)
        
        return try ScheduleInfo.fetchAll(db, request)
    }
}

struct SemestersRequest: ValueObservationQueryable {
    static var defaultValue: [Semester] {
        []
    }
    var college: College?
    var date: Date?

    func fetch(_ db: Database) throws -> [Semester] {
        guard let college = college else {
            return []
        }

        if let date {
            return try Semester
                .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
                .fetchAll(db)
        }

        return try Semester
            .filter(Column("college") == college)
            .order(Column("start_at").desc)
            .fetchAll(db)
    }
}

class Eloquent {
    static var pool: DatabasePool?

    /// Returns an initialized database pool at the shared location databaseURL
    static func openSharedDatabase(at databaseURL: URL) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var dbPool: DatabasePool?
        var dbError: Error?
        coordinator.coordinate(writingItemAt: databaseURL, options: .forMerging, error: &coordinatorError) { url in
            do {
                dbPool = try openDatabase(at: url)
            } catch {
                dbError = error
            }
        }
        if let error = dbError ?? coordinatorError {
            throw error
        }
        return dbPool!
    }


    static private func openDatabase(at databaseURL: URL) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Activate the persistent WAL mode so that
            // read-only processes can access the database.
            //
            // See https://www.sqlite.org/walformat.html#operations_that_require_locks_and_which_locks_those_operations_use
            // and https://www.sqlite.org/c3ref/c_fcntl_begin_atomic_write.html#sqlitefcntlpersistwal
            if db.configuration.readonly == false {
                var flag: CInt = 1
                let code = withUnsafeMutablePointer(to: &flag) { flagP in
                    sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, flagP)
                }
                guard code == SQLITE_OK else {
                    throw DatabaseError(resultCode: ResultCode(rawValue: code))
                }
            }
        }
        let dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        return dbPool
    }
    
    /// Returns an initialized database pool at the shared location databaseURL,
    /// or nil if the database is not created yet, or does not have the required
    /// schema version.
    static func openSharedReadOnlyDatabase(at databaseURL: URL) throws -> DatabasePool? {
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

    static private func openReadOnlyDatabase(at databaseURL: URL) throws -> DatabasePool? {
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
    
    static func initReadWrite() throws {
        do {
            let dbURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.boar.sjct")!
                .appendingPathComponent("class_table.db")

            Eloquent.pool = try openSharedDatabase(at: dbURL)
        } catch {
            throw error
        }
    }
    
    static func initReadOnly() throws {
        do {
            let dbURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.boar.sjct")!
                .appendingPathComponent("class_table.db")

            Eloquent.pool = try openSharedReadOnlyDatabase(at: dbURL)
        } catch {
            throw error
        }
    }
    
    static func migrate() throws {
        guard let pool else {
            throw EloquentError.dbNotOpened
        }
        
        var migrator = DatabaseMigrator()

        // v1
        migrator.registerMigration("initialize") { db in
            try db.create(table: "semesters", ifNotExists: true) { t in
                t.column("id", .text)
                t.column("college", .integer)
                t.column("year", .integer)
                t.column("semester", .integer)
                t.column("start_at", .date)
                t.column("end_at", .date)

                t.uniqueKey(["id", "college"], onConflict: .replace)
            }
            
            try db.create(table: "organizations", ifNotExists: true) { t in
                t.column("id", .text)
                t.column("college", .integer)
                t.column("name", .text)

                t.uniqueKey(["id", "college"], onConflict: .replace)
            }

            try db.create(table: "courses", ifNotExists: true) { t in
                t.column("code", .text)
                t.column("college", .integer)
                t.column("name", .text)

                t.uniqueKey(["code", "college"], onConflict: .replace)
            }

            try db.create(table: "classes", ifNotExists: true) { t in
                t.column("id", .text)
                t.column("college", .integer)
                t.column("color", .text)
                t.column("course_code", .text)
                t.column("organization_id", .text)
                t.column("name", .text)
                t.column("code", .text)
                t.column("teachers", .text)
                t.column("hours", .real)
                t.column("credits", .real)
                t.column("semester_id", .text)

                t.uniqueKey(["id", "college"], onConflict: .replace)
                t.foreignKey(["course_code", "college"], references: "courses", columns: ["code", "college"])
                t.foreignKey(["organization_id", "college"], references: "organizations", columns: ["id", "college"])
                t.foreignKey(["semester_id", "college"], references: "semesters", columns: ["id", "college"])
            }

            try db.create(table: "schedules", ifNotExists: true) { t in
                t.column("class_id", .text)
                t.column("college", .integer)
                t.column("classroom", .text)
                t.column("day", .integer)
                t.column("period", .integer)
                t.column("week", .integer)
                t.column("is_start", .integer)
                t.column("length", .integer)

                t.uniqueKey(["class_id", "college", "day", "period", "week"], onConflict: .replace)
                t.foreignKey(["class_id", "college"], references: "classes", columns: ["id", "college"])
            }
            
            try db.create(table: "class_remarks", ifNotExists: true) { t in
                t.column("class_id", .text)
                t.column("college", .integer)
                t.column("remark", .text)

                t.uniqueKey(["class_id", "college"], onConflict: .replace)
                t.foreignKey(["class_id", "college"], references: "classes", columns: ["id", "college"])
            }

            try db.create(table: "exams", ifNotExists: true) { t in
                t.column("class_id", .text)
                t.column("college", .integer)
                t.column("campus", .text)
                t.column("classroom", .text)
                t.column("date", .text)
                t.column("start_at", .integer)
                t.column("end_at", .integer)
                t.column("exam_id", .text)
                t.column("examp_id", .text)
                t.column("exam_type", .text)
                t.column("method", .text)
                t.column("name", .text)

                t.uniqueKey(["class_id", "college", "exam_id", "examp_id"], onConflict: .replace)
                t.foreignKey(["class_id", "college"], references: "classes", columns: ["id", "college"])
            }
            
            try db.create(table: "canvas_lms", ifNotExists: true) { t in
                t.column("id", .text)
                t.column("college", .integer)
                t.column("class_id", .text)

                t.uniqueKey(["id", "college"], onConflict: .replace)
                t.foreignKey(["class_id", "college"], references: "classes", columns: ["id", "college"])
            }
        }
        
        try migrator.migrate(pool)
    }

    static func getSemester(college: College, date: Date) throws -> Semester? {
        guard let connection = Eloquent.pool else {
            throw EloquentError.dbNotOpened
        }

        return try connection.read { db in
            try Semester
                .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
                .fetchOne(db)
        }
    }
    
    static func getSchedules(college: College, date: Date) throws -> [ScheduleInfo] {
        guard let connection = Eloquent.pool else {
            throw EloquentError.dbNotOpened
        }
        
        let semester = try connection.read { db in
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
        
        return try connection.read { db in
            try ScheduleInfo.fetchAll(db, request)
        }
    }
    
    static func insertSchedules(semester: Semester, college: College, schedules: [CourseClassSchedule], deleteExisting: Bool = false) async throws {
        guard let connection = Eloquent.pool else {
            throw EloquentError.dbNotOpened
        }
        
        try await connection.write { db in
            if deleteExisting {
                try Schedule
                    .including(required: Schedule.class_
                        .filter(Column("semester_id") == semester.id && Column("college") == college))
                    .deleteAll(db)
            }
            try schedules.forEach { relation in
                try relation.organization?.save(db)
                try relation.course.save(db)
                try relation.class_.save(db)
                try relation.schedules.forEach { schedule in
                    try schedule.save(db)
                }
                try relation.remarks?.forEach { remark in
                    try remark.save(db)
                }
            }
        }
    }
}
