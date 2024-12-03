//
//  Date.swift
//  MySJTU
//
//  Created by boar on 2024/10/20.
//

import Foundation

extension Calendar {
    static var iso8601: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
        return calendar
    }
}

extension Date {
    func get(_ components: Calendar.Component..., calendar: Calendar = .iso8601) -> DateComponents {
        return calendar.dateComponents(Set(components), from: self)
    }
    
    func get(_ component: Calendar.Component, calendar: Calendar = .iso8601) -> Int {
        return calendar.component(component, from: self)
    }
    
    static func fromFormat(_ format: String, dateStr: String, calendar: Calendar = .iso8601) -> Date? {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.date(from: dateStr)
    }
    
    func startOfWeek(using calendar: Calendar = .iso8601) -> Date {
        calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: self).date!
    }
    
    func startOfDay(using calendar: Calendar = .iso8601) -> Date {
        calendar.startOfDay(for: self)
    }
    
    func weekDays(using calendar: Calendar = .iso8601) -> [Date] {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: self)?.start else {
            return []
        }
        
        var weekDates: [Date] = []
        for i in 0..<7 {
            if let nextDay = calendar.date(byAdding: .day, value: i, to: weekStart) {
                weekDates.append(nextDay)
            }
        }
        
        return weekDates
    }
    
    func isSameDay(as date: Date, using calendar: Calendar = .iso8601) -> Bool {
        return calendar.isDate(date, inSameDayAs: self)
    }
    
    func isToday(using calendar: Calendar = .iso8601) -> Bool {
        return calendar.isDateInToday(self)
    }
    
    func localeWeekday(using calendar: Calendar = .iso8601) -> String {
        return "周\(["", "日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: self)])"
    }
    
    func localeMonth(using calendar: Calendar = .iso8601) -> String {
        return "\(calendar.component(.month, from: self))月"
    }
    
    func weeksSince(_ date: Date, using calendar: Calendar = .iso8601) -> Int {
        Int(self.startOfWeek().timeIntervalSince(date.startOfWeek()) / (7 * 60 * 60 * 24))
    }
    
    func daysSince(_ date: Date, using calendar: Calendar = .iso8601) -> Int {
        Int(self.startOfDay().timeIntervalSince(date.startOfDay()) / (60 * 60 * 24))
    }
    
    func minutesSince(_ date: Date, using calendar: Calendar = .iso8601) -> Int {
        Int(self.startOfDay().timeIntervalSince(date.startOfDay()) / 60)
    }
    
    func addDays(_ days: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .day, value: days, to: noon(using: calendar))!
    }
    
    func addHours(_ hours: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: self)!
    }
    
    func addWeeks(_ weeks: Int, using calendar: Calendar = .iso8601) -> Date {
        addDays(weeks * 7, using: calendar)
    }
    
    func timeOfDay(_ format: String, timeStr: String, using calendar: Calendar = .iso8601) -> Date? {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        if let target = formatter.date(from: timeStr) {
            return calendar.date(bySettingHour: target.get(.hour, calendar: calendar), minute: target.get(.minute, calendar: calendar), second: target.get(.second, calendar: calendar), of: self)
        }
        return nil
    }

    func noon(using calendar: Calendar = .iso8601) -> Date {
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: self)!
    }
    
    func formattedDate(using calendar: Calendar = .iso8601) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
