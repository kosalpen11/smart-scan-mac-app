import Foundation

// MARK: - Schedule

enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: "Manually"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

struct Schedule: Codable, Hashable, Sendable {
    var frequency: ScheduleFrequency = .weekly
    /// 0–23
    var hour: Int = 9
    /// 1 = Sunday … 7 = Saturday (Calendar convention)
    var weekday: Int = 2
    /// 1–28, so every month has the day
    var dayOfMonth: Int = 1

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        components.second = 0
        switch frequency {
        case .manual: return nil
        case .daily: break
        case .weekly: components.weekday = weekday
        case .monthly: components.day = dayOfMonth
        }
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }

    var description: String {
        let time = Schedule.hourText(hour)
        switch frequency {
        case .manual: return "Manually"
        case .daily: return "Daily at \(time)"
        case .weekly: return "Every \(Schedule.weekdayName(weekday)) at \(time)"
        case .monthly: return "Monthly on day \(dayOfMonth) at \(time)"
        }
    }

    static func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = Calendar.current.weekdaySymbols
        return names[(max(1, min(7, weekday))) - 1]
    }
}
