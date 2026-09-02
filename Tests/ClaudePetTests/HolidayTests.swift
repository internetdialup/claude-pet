import Testing
import Foundation
@testable import ClaudePet

/// The seasonal calendar, pinned against a FIXED calendar — Gregorian, UTC —
/// so no machine's locale or zone can move a boundary under the suite. Every
/// date is injected; nothing here reads a clock.
@Suite("The holiday calendar")
struct HolidayTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Day-before / first-day / last-day / day-after, per holiday, across the
    /// years — Thanksgiving from its own anchor table, computed nowhere else.
    @Test func windowBoundaries() {
        // The 4th Thursday of November, 2025–2030, verified by hand.
        let thanksgiving = [2025: 27, 2026: 26, 2027: 25, 2028: 23, 2029: 22, 2030: 28]

        for year in 2025...2030 {
            let anchor = thanksgiving[year]!
            let table: [(Holiday, Date, Date)] = [
                (.halloween, day(year, 10, 18), day(year, 10, 31)),
                (.thanksgiving, day(year, 11, anchor - 13), day(year, 11, anchor)),
                (.winter, day(year, 12, 11), day(year, 12, 25)),
                (.newYear, day(year, 12, 26), day(year + 1, 1, 1)),
            ]
            for (holiday, first, last) in table {
                let before = calendar.date(byAdding: .day, value: -1, to: first)!
                let after = calendar.date(byAdding: .day, value: 1, to: last)!
                #expect(Holiday.current(on: first, calendar: calendar) == holiday,
                        "\(holiday) missing on its first day, \(year)")
                #expect(Holiday.current(on: last, calendar: calendar) == holiday,
                        "\(holiday) missing on its last day, \(year)")
                #expect(Holiday.current(on: before, calendar: calendar) != holiday,
                        "\(holiday) leaked a day early, \(year)")
                #expect(Holiday.current(on: after, calendar: calendar) != holiday,
                        "\(holiday) overstayed a day, \(year)")
            }
        }
    }

    /// Every day of a plain year AND a leap year answers at most one holiday
    /// — the calendar was designed so the sweep is a theorem, not a tie-break.
    @Test func noDayServesTwoHolidays() {
        for year in [2027, 2028] {   // 2028 is the leap year
            var date = day(year, 1, 1)
            let end = day(year + 1, 1, 1)
            while date < end {
                let owners = Holiday.allCases.filter { holiday in
                    [year, year - 1].contains { y in
                        holiday.window(in: y, calendar: calendar)?.contains(date) == true
                    }
                }
                #expect(owners.count <= 1, "\(date) belongs to \(owners)")
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
    }

    /// Jan 1 belongs to the OLD year's New Year window, and the greeted-key
    /// year is stable across the straddle.
    @Test func newYearStraddlesTheYear() {
        #expect(Holiday.current(on: day(2027, 1, 1), calendar: calendar) == .newYear)
        #expect(Holiday.current(on: day(2027, 1, 2), calendar: calendar) == nil)
        #expect(Holiday.newYear.seasonYear(for: day(2026, 12, 28), calendar: calendar) == 2026)
        #expect(Holiday.newYear.seasonYear(for: day(2027, 1, 1), calendar: calendar) == 2026)
    }

    /// The menu gate: evergreens always; a seasonal look only inside its
    /// window. Rendering is never consulted here — that is the point.
    @Test func availabilityFollowsTheWindow() {
        let midsummer = day(2027, 6, 15)
        for costume in Costume.allCases where costume.holiday == nil {
            #expect(costume.isAvailable(on: midsummer, calendar: calendar))
        }
        #expect(!Costume.pumpkin.isAvailable(on: midsummer, calendar: calendar))
        #expect(Costume.pumpkin.isAvailable(on: day(2027, 10, 20), calendar: calendar))
        #expect(!Costume.pumpkin.isAvailable(on: day(2027, 11, 1), calendar: calendar))
        #expect(Costume.turkey.isAvailable(on: day(2026, 11, 26), calendar: calendar))
        #expect(Costume.santa.isAvailable(on: day(2026, 12, 25), calendar: calendar))
        #expect(!Costume.santa.isAvailable(on: day(2026, 12, 26), calendar: calendar))
    }

    /// The auto-wear policy: greet once with a stash, restore at expiry,
    /// no-op everywhere else.
    @Test func wardrobeVerdicts() {
        let oct20 = day(2026, 10, 20), july = day(2026, 7, 4)

        // First launch in the window: stash the worn look, wear the season's.
        #expect(HolidayWardrobe.atLaunch(now: oct20, worn: .ninja, stashed: nil,
                                         alreadyGreeted: false, calendar: calendar)
                == HolidayWardrobe.Verdict(wear: .pumpkin, stash: .ninja, markGreeted: true))
        // Already greeted: leave the user's choice alone — even Classic.
        #expect(HolidayWardrobe.atLaunch(now: oct20, worn: .none, stashed: .ninja,
                                         alreadyGreeted: true, calendar: calendar)
                == HolidayWardrobe.Verdict())
        // Already wearing it: nothing to do, and no greeted-mark burned.
        #expect(HolidayWardrobe.atLaunch(now: oct20, worn: .pumpkin, stashed: .ninja,
                                         alreadyGreeted: false, calendar: calendar)
                == HolidayWardrobe.Verdict())
        // Window over, seasonal still on: back to the stash, stash cleared.
        #expect(HolidayWardrobe.atLaunch(now: july, worn: .pumpkin, stashed: .ninja,
                                         alreadyGreeted: true, calendar: calendar)
                == HolidayWardrobe.Verdict(wear: .ninja, clearStash: true))
        // Window over, no stash recorded: Classic. (`Costume.none` spelled
        // out — in this Optional position a bare `.none` is nil, the exact
        // ambiguity the Verdict doc warns about.)
        #expect(HolidayWardrobe.atLaunch(now: july, worn: .santa, stashed: nil,
                                         alreadyGreeted: false, calendar: calendar)
                == HolidayWardrobe.Verdict(wear: Costume.none, clearStash: true))
        // Plain summer day, plain wardrobe: nothing happens.
        #expect(HolidayWardrobe.atLaunch(now: july, worn: .tiger, stashed: nil,
                                         alreadyGreeted: false, calendar: calendar)
                == HolidayWardrobe.Verdict())
    }
}
