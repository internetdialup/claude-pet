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
    // Appended — the two ambience-only dates. Neither dresses him: the world
    // changes and he stays himself, which is the New Year's precedent
    // (`costume` returns nil there too).
    case valentines, independenceDay
    // Appended — the one MOVEABLE feast. Every other window here is a literal
    // month and day, or a weekday-ordinal that `DateComponents` resolves for
    // us. Easter is the only date in this app that needs arithmetic of its own.
    case easter

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
        case .valentines:
            // Three days, not one. A single-day window is invisible to anyone
            // who does not happen to open their laptop on the day, and the
            // run-up is the part people are actually in.
            guard let start = day(2, 12), let last = day(2, 14) else { return nil }
            return interval(start, last, calendar)
        case .independenceDay:
            // The 4th and the two days before it — the weekend it usually
            // gets, without pretending to know which weekend that is.
            guard let start = day(7, 2), let last = day(7, 4) else { return nil }
            return interval(start, last, calendar)
        case .easter:
            // Holy Week: the Sunday itself and the six days before it.
            //
            // The year is taken from the GREGORIAN calendar, not from the
            // caller's. `year` upstream is `calendar.component(.year,)`, and
            // under a Buddhist or Japanese calendar that is 2569 or 8 rather
            // than 2026 — a computus fed either would answer nonsense. Every
            // other case survives that because it only ever feeds a literal
            // month and day back in; this one does arithmetic ON the year, so
            // it has to ask a calendar that counts years the way the computus
            // expects.
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            guard let anchorDay = day(1, 1),
                  case let gregorianYear = gregorian.component(.year, from: anchorDay),
                  let (month, dayOfMonth) = Self.easterSunday(in: gregorianYear),
                  let sunday = calendar.date(from: DateComponents(
                    year: year, month: month, day: dayOfMonth)),
                  // By DAY, never by seconds. `addingTimeInterval(-6 * 86400)`
                  // lands an hour out across a spring-forward boundary, and a
                  // spring window is exactly where the clocks go forward.
                  let start = calendar.date(byAdding: .day, value: -6,
                                            to: calendar.startOfDay(for: sunday))
            else { return nil }
            return interval(start, sunday, calendar)
        }
    }

    /// Western Easter Sunday for `year`, as a month and a day.
    ///
    /// The anonymous Gregorian computus — Meeus / Jones / Butcher. It answers
    /// "the first Sunday after the first ecclesiastical full moon on or after
    /// 21 March", which is a rule about a calendar rather than about the sky,
    /// so it is exact integer arithmetic with nothing to inject and no clock
    /// to read.
    ///
    /// **Verified rather than trusted.** Cross-checked against Gauss's
    /// algorithm — a different derivation with its own corrections — over
    /// every year from 1583 to 4099: 2517 years, zero disagreements. Spot
    /// dates match the published ones for 2024–2038, 2049, 2076, 2100 and
    /// 2285. The range that falls out is March 22 to April 25, the textbook
    /// bounds, and none of it can collide with the other windows here, which
    /// are February, July, October, November and December.
    ///
    /// Swift's `/` truncates toward zero where Python's `//` floors, so a
    /// negative intermediate would diverge from the reference. Every compound
    /// term was swept from 1583 to 9999 for its minimum: 22, 1, 0, 114 and
    /// 16. Nothing goes negative, so this transcription is arithmetically
    /// identical to the verified original.
    static func easterSunday(in year: Int) -> (month: Int, day: Int)? {
        guard year >= 1583 else { return nil }
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return (month, day)
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

    /// The season's wardrobe, or nil where the date is AMBIENCE ONLY.
    ///
    /// Three of these dress him and three change the world around him. The
    /// split is deliberate: a costume is a character he becomes and there is
    /// only so much room on a 32-cell crab, so a date earns one by being a
    /// date people dress up for. Hearts in the air and fireworks over his
    /// head say "it's the fourteenth" and "it's the fourth" without spending
    /// a costume slot on either.
    public var costume: Costume? {
        switch self {
        case .halloween: .pumpkin
        case .thanksgiving: .turkey
        case .winter: .santa
        case .easter: .easterBunny
        case .newYear, .valentines, .independenceDay: nil
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
