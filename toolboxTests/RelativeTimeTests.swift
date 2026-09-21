//
//  RelativeTimeTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import Testing
@testable import toolbox

/// Bucketing assertions compare against the same localized strings evaluated
/// in the current environment, so they hold in any simulator language.
struct RelativeTimeTests {
    // Fixed reference point: 2026-09-19 12:00:00 UTC (a Saturday).
    private let now = Date(timeIntervalSince1970: 1_789_756_800)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func ago(_ seconds: TimeInterval) -> String {
        RelativeTime.string(from: now.addingTimeInterval(-seconds), now: now, calendar: calendar)
    }

    @Test func relativeBuckets() {
        #expect(ago(30) == String(localized: "Just now", bundle: .main))
        #expect(ago(59) == String(localized: "Just now", bundle: .main))
        #expect(ago(60) == String(localized: "\(1) min ago", bundle: .main))
        #expect(ago(45 * 60) == String(localized: "\(45) min ago", bundle: .main))
        #expect(ago(3600) == String(localized: "\(1) hr ago", bundle: .main))
        #expect(ago(23 * 3600) == String(localized: "\(23) hr ago", bundle: .main))
    }

    @Test func calendarDayBuckets() {
        // 25 hours ago: 2026-09-18 11:00 UTC, i.e. calendar yesterday.
        #expect(ago(25 * 3600) == String(localized: "Yesterday", bundle: .main))
        // 49 hours ago: calendar day before yesterday.
        #expect(ago(49 * 3600) == String(localized: "Day before yesterday", bundle: .main))
        // 72 hours ago falls into the days bucket.
        #expect(ago(72 * 3600) == String(localized: "\(3) days ago", bundle: .main))
        #expect(ago(30 * 86400) == String(localized: "\(30) days ago", bundle: .main))
    }

    @Test func absoluteDates() {
        // 2026-01-15: same year, more than 30 days ago -> month + day.
        let sameYear = RelativeTime.string(
            from: Date(timeIntervalSince1970: 1_769_630_400),
            now: now,
            calendar: calendar
        )
        #expect(sameYear == Date(timeIntervalSince1970: 1_769_630_400).formatted(.dateTime.month().day()))
        // 2024-05-01: another year -> full date.
        let old = RelativeTime.string(
            from: Date(timeIntervalSince1970: 1_714_521_600),
            now: now,
            calendar: calendar
        )
        #expect(old == Date(timeIntervalSince1970: 1_714_521_600).formatted(.dateTime.year().month().day()))
    }
}
