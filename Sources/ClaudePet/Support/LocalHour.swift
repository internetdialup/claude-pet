import Foundation

/// The local hour, memoised until the hour actually turns.
///
/// Two schedules are gated on the time of day — the midnight stargazer and the
/// afternoon patch of sun — and the view asked `Calendar` for the hour on
/// **every frame**, twice (once for the pose, once for the tint). At idle's
/// 20fps that is forty `Calendar` round-trips a second, and a wake window is
/// fifteen minutes long: roughly thirty-six thousand of them to answer a
/// question whose answer changes once an hour.
///
/// It also closes a small purity wart. Everything around it is a function of
/// the frame's `time`; this alone reached for `Date()`, so at the coarse frame
/// rates the pose and the tint could in principle straddle an hour boundary
/// differently and disagree about what time it was inside one frame. Asking
/// once and caching to the boundary makes that impossible.
///
/// `@MainActor` because the view is the only caller and a shared mutable cache
/// wants one owner, not a lock.
@MainActor
enum LocalHour {
    private static var cached: (hour: Int, validUntil: Date)?

    /// The local hour right now.
    static var current: Int {
        let now = Date()
        if let cached, now < cached.validUntil { return cached.hour }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        // Valid until the top of the next hour. `nextDate` handles the awkward
        // cases a manual `+3600` gets wrong — DST transitions, and calendars
        // where an hour is not sixty minutes.
        let boundary = calendar.nextDate(after: now,
                                         matching: DateComponents(minute: 0, second: 0),
                                         matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(60)
        cached = (hour, boundary)
        return hour
    }

    /// Drops the memo. Tests only — the app has no reason to.
    static func invalidate() { cached = nil }
}
