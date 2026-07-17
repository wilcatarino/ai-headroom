import Foundation

public func countdown(to date: Date?, now: Date) -> String {
    guard let date else { return "-" }
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return "-" }
    let days = secs / 86400
    let hours = (secs % 86400) / 3600
    let mins = (secs % 3600) / 60
    if days > 0 { return "\(days)d\(hours)h" }
    if hours > 0 { return "\(hours)h\(String(format: "%02d", mins))m" }
    if mins > 0 { return "\(mins)m" }
    return "<1m"
}

public func relativeTime(since date: Date, now: Date) -> String {
    let secs = Int(now.timeIntervalSince(date))
    if secs < 60 { return "agora" }
    let mins = secs / 60
    if mins < 60 { return "há \(mins)min" }
    let hours = mins / 60
    if hours < 24 { return "há \(hours)h" }
    return "há \(hours / 24)d"
}

public func clockLabel(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
    guard let date else { return "-" }
    let f = DateFormatter()
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.locale = Locale(identifier: "pt_BR")
    if calendar.isDate(date, inSameDayAs: now) {
        f.dateFormat = "HH:mm"
    } else {
        f.dateFormat = "dd/MM HH:mm"
    }
    return f.string(from: date)
}
