//
//  RelativeTime.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import Foundation

/// Formats a date as relative text: "Just now" under a minute, minutes under
/// an hour, hours under a day, then "Yesterday" / "Day before yesterday" /
/// "X days ago" within 30 days, then month-day within the current year and
/// full date otherwise.
enum RelativeTime {
    static func string(from date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return String(localized: "Just now")
        }
        if elapsed < 3600 {
            return String(localized: "\(Int(elapsed / 60)) min ago")
        }
        if elapsed < 86400 {
            return String(localized: "\(Int(elapsed / 3600)) hr ago")
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days == 1 {
            return String(localized: "Yesterday")
        }
        if days == 2 {
            return String(localized: "Day before yesterday")
        }
        if days <= 30 {
            return String(localized: "\(days) days ago")
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month().day())
        }
        return date.formatted(.dateTime.year().month().day())
    }
}
