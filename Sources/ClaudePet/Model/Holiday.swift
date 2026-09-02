import Foundation

/// The seasonal calendar: four windows a year when the costume menu grows and
/// the weather changes. Model-layer, Foundation-only, and every date is
/// injectable — the tests pin a fixed calendar, and nothing here ever reads a
/// clock of its own.
///
/// The windows (all inclusive, in the user's local calendar):
/// - **Halloween**: Oct 18 – Oct 31 — the last two weeks.
/// - **Thanksgiving** (US): the 13 days before the 4th Thursday of November,
///   and the day itself. Computed, never tabled — the anchor moves.
/// - **Winter**: Dec 11 – Dec 25.
/// - **New Year**: Dec 26 – Jan 1. One week, not two, and that is a
///   deliberate bend of the last-two-weeks rule: the literal rule would
///   overlap Winter, and splitting the season at Christmas night gives every
///   day exactly one owner — the no-overlap sweep is a theorem instead of a
///   tie-break. Jan 1 belongs to the PREVIOUS year's window.
public enum Holiday: String, CaseIterable, Sendable {
    case halloween, thanksgiving, winter, newYear

    /// The window for this holiday anchored in `year` — half-open, from the
    /// first day's midnight to the midnight after the last day. All arithmetic
    /// goes through `Calendar` (never raw epoch math), so DST cannot shear it.
    public func window(in year: Int, calendar: Calendar = .current) -> DateInterval? {
        func day(_ month: Int, _ day: Int, _ y: Int = year) -> Date? {
            calendar.date(from: DateComponents(year: y, month: month, day: day))
        }
        switch self {
        case .halloween:
            guard let start = day(10, 18), let last = day(10, 31) else { return nil }
            return interval(start, last, calendar)
        case .thanksgiving:
            // The 4th Thursday of November, straight from DateComponents —
            // weekday 5 is Thursday in the Gregorian numbering.
            guard let anchor = calendar.date(from: DateComponents(
                year: year, month: 11, weekday: 5, weekdayOrdinal: 4)),
                let start = calendar.date(byAdding: .day, value: -13,
                                          to: calendar.startOfDay(for: anchor))
            else { return nil }
            return interval(start, anchor, calendar)
        case .winter:
            guard let start = day(12, 11), let last = day(12, 25) else { return nil }
            return interval(start, last, calendar)
        case .newYear:
            guard let start = day(12, 26), let last = day(1, 1, year + 1) else { return nil }
            return interval(start, last, calendar)
        }
    }

    private func interval(_ first: Date, _ last: Date, _ calendar: Calendar) -> DateInterval? {
        let start = calendar.startOfDay(for: first)
        guard let end = calendar.date(byAdding: .day, value: 1,
                                      to: calendar.startOfDay(for: last)) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The one holiday owning this instant, or nil. Checks this year's
    /// windows and the previous year's — Jan 1 sits inside the OLD year's
    /// New Year window and nowhere else.
    public static func current(on date: Date = Date(),
                               calendar: Calendar = .current) -> Holiday? {
        let year = calendar.component(.year, from: date)
        for y in [year, year - 1] {
            for holiday in allCases {
                if holiday.window(in: y, calendar: calendar)?.contains(date) == true {
                    return holiday
                }
            }
        }
        return nil
    }

    /// The season's wardrobe — nil for New Year, which is ambience only.
    public var costume: Costume? {
        switch self {
        case .halloween: .pumpkin
        case .thanksgiving: .turkey
        case .winter: .santa
        case .newYear: nil
        }
    }

    /// The year the window STARTS in — the auto-wear greeted-key's year
    /// component, stable across the New Year straddle: Dec 28 and Jan 1 of
    /// the same window answer the same year.
    public func seasonYear(for date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        if window(in: year, calendar: calendar)?.contains(date) == true { return year }
        return year - 1
    }
}

extension Costume {
    /// Whether the menu offers this look today. RENDERING is never gated on
    /// this — tests, the sizzle montage and the sampler draw every case
    /// date-free; the date decides only what the menu lists and what the
    /// wardrobe policy wears.
    public func isAvailable(on date: Date = Date(),
                            calendar: Calendar = .current) -> Bool {
        guard let holiday else { return true }
        return Holiday.current(on: date, calendar: calendar) == holiday
    }

    /// The window this costume belongs to — nil for the evergreen wardrobe.
    public var holiday: Holiday? {
        switch self {
        case .pumpkin: .halloween
        case .turkey: .thanksgiving
        case .santa: .winter
        default: nil
        }
    }
}

/// The auto-wear-once policy, pure: what to wear at launch, what to stash,
/// and whether to mark the season greeted. `AppDelegate` is a two-line shim
/// over this, which is what makes the policy fixture-testable.
public enum HolidayWardrobe {
    public struct Verdict: Equatable, Sendable {
        /// Change into this, or nil to leave the wardrobe alone.
        public var wear: Costume?
        /// Store this as the pre-season stash, or nil to leave the stash.
        /// Distinct from `clearStash` because Classic is a real costume — a
        /// stash OF `.none` and NO stash are different facts.
        public var stash: Costume?
        /// Forget the stash — the season is over and it has been restored.
        public var clearStash: Bool
        /// Record the season as greeted.
        public var markGreeted: Bool
        public init(wear: Costume? = nil, stash: Costume? = nil,
                    clearStash: Bool = false, markGreeted: Bool = false) {
            self.wear = wear
            self.stash = stash
            self.clearStash = clearStash
            self.markGreeted = markGreeted
        }
    }

    /// - a worn seasonal costume whose window has closed reverts to the
    ///   stash (or Classic), clearing it;
    /// - inside a costume-bearing window not yet greeted, the seasonal look
    ///   goes on ONCE, stashing whatever was worn — the user can switch
    ///   straight back, and a re-launch will not re-dress them;
    /// - anything else is a no-op.
    public static func atLaunch(now: Date, worn: Costume, stashed: Costume?,
                                alreadyGreeted: Bool,
                                calendar: Calendar = .current) -> Verdict {
        if worn.holiday != nil, !worn.isAvailable(on: now, calendar: calendar) {
            return Verdict(wear: stashed ?? Costume.none, clearStash: true)
        }
        if let holiday = Holiday.current(on: now, calendar: calendar),
           let seasonal = holiday.costume,
           !alreadyGreeted, worn != seasonal {
            return Verdict(wear: seasonal, stash: worn, markGreeted: true)
        }
        return Verdict()
    }
}
