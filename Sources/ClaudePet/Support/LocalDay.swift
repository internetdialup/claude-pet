import Foundation

/// The wall-calendar's answer to "which holiday is it", memoized to midnight —
/// `LocalHour`'s silhouette, one flight up. The answer changes once a day, and
/// one memoized read means the pose and any future consumer cannot disagree
/// inside a frame.
///
/// Live-only by the same double lock as the hour: `CrabView` consults this
/// solely when `frozenTime == nil`, and the animator takes the RESOLVED
/// `Holiday?` as a default-nil parameter — offline renderers pass nothing and
/// can never see a season.
@MainActor
enum LocalDay {
    private static var cached: (holiday: Holiday?, validUntil: Date)?

    static var holiday: Holiday? {
        let now = Date()
        if let cached, now < cached.validUntil { return cached.holiday }
        let calendar = Calendar.current
        let midnight = calendar.nextDate(after: now,
                                         matching: DateComponents(hour: 0, minute: 0, second: 0),
                                         matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        let answer = Holiday.current(on: now, calendar: calendar)
        cached = (answer, midnight)
        return answer
    }

    /// Tests only: forget the memo so an injected date change is seen.
    static func invalidate() { cached = nil }
}
