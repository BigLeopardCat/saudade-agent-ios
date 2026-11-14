import Foundation

public enum ChatTime {
    public static func date(milliseconds: Double?) -> Date? {
        guard let value = milliseconds, value.isFinite, value > 0, value <= 253_402_300_799_000 else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
    /// Mirrors Agent chat-core.js: first valid timestamp and adjacent gaps strictly over five minutes.
    public static func shouldShow(previous: Date?, current: Date?) -> Bool {
        guard let current else { return false }
        guard let previous else { return true }
        return current.timeIntervalSince(previous) > 300
    }
    public static func label(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return clock }
        if days == 1 { return "昨天 " + clock }
        let day = "\(parts.month ?? 1)月\(parts.day ?? 1)日 "
        if parts.year == calendar.component(.year, from: now) { return day + clock }
        return "\(parts.year ?? 1970)年" + day + clock
    }
}
