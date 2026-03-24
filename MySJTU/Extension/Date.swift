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
    
    func secondsFromTime(_ date: Date) -> Int {
        let calendar: Calendar = .iso8601
        let toTime = calendar.dateComponents([.hour, .minute, .second], from: self)
        let fromTime = calendar.dateComponents([.hour, .minute, .second], from: date)
        
        let diff = calendar.dateComponents([.hour, .minute, .second], from: fromTime, to: toTime)
        
        return diff.hour! * 3600 + diff.minute! * 60 + diff.second!
    }
    
    func startOfWeek(using calendar: Calendar = .iso8601) -> Date {
        calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: self).date!
    }
    
    func startOfDay(using calendar: Calendar = .iso8601) -> Date {
        calendar.startOfDay(for: self)
    }
    
    func startOfMonth(using calendar: Calendar = .iso8601) -> Date {
        calendar.dateComponents([.calendar, .year, .month], from: self).date!
    }
    
    func endOfMonth(using calendar: Calendar = .iso8601) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: startOfMonth())
        
        components.hour = 23
        components.minute = 59
        components.second = 59
                
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: calendar.date(from: components)!)!
    }
    
    func startOfHour(using calendar: Calendar = .iso8601) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: self)

        components.minute = 0
        components.second = 0
        components.nanosecond = 0

        return calendar.date(from: components)!
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
        let days = calendar.dateComponents(
            [.day],
            from: date.startOfWeek(using: calendar),
            to: self.startOfWeek(using: calendar)
        ).day ?? 0
        return days / 7
    }
    
    func daysSince(_ date: Date, using calendar: Calendar = .iso8601) -> Int {
        calendar.dateComponents(
            [.day],
            from: date.startOfDay(using: calendar),
            to: self.startOfDay(using: calendar)
        ).day ?? 0
    }
    
    func minutesSince(_ date: Date, using calendar: Calendar = .iso8601) -> Int {
        Int(self.startOfDay().timeIntervalSince(date.startOfDay()) / 60)
    }
    
    func addMonths(_ months: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .month, value: months, to: self)!
    }
    
    func addDays(_ days: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .day, value: days, to: self)!
    }
    
    func addHours(_ hours: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: self)!
    }
    
    func addMinutes(_ minutes: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: self)!
    }
    
    func addSeconds(_ seconds: Int, using calendar: Calendar = .iso8601) -> Date {
        calendar.date(byAdding: .second, value: seconds, to: self)!
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
    
    func timeOfDay(hour: Int, minute: Int, using calendar: Calendar = .iso8601) -> Date? {
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: self)
    }
    
    func noon(using calendar: Calendar = .iso8601) -> Date {
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: self)!
    }
    
    func formatted(format: String, using calendar: Calendar = .iso8601) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    func formattedDate(using calendar: Calendar = .iso8601) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
    
    func formattedRelativeDate(using calendar: Calendar = .iso8601) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: self)
    }
    
    func formattedMonthDay(format: String = "MM-dd", using calendar: Calendar = .iso8601) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    func timeIsBefore(_ date: Date) -> Bool {
        if self.get(.hour) < date.get(.hour) {
            return true
        }

        if self.get(.hour) > date.get(.hour) {
            return false
        }
        
        if self.get(.minute) < date.get(.minute) {
            return true
        }
        
        return false
    }
}
