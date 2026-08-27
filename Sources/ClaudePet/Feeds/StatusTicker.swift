import Foundation

/// Builds the short status lines Claw'd scrolls between shout-outs.
///
/// **Numerical Grounding**: every percentage here is copied
/// from a number Claude Code itself wrote to disk. Nothing is inferred, and a
/// figure that is absent or stale produces no line rather than a guess — a
/// confidently wrong "82%" is worse than saying nothing.
public enum StatusTicker {

    /// Written by the user's `statusLine` command, if they run one. Absent for
    /// most installs, and its fields go null when Claude Code stops publishing
    /// rate limits — both handled by returning no line.
    struct UsageCache: Decodable {
        let writtenAt: Double?
        let fiveHourPercent: Double?
        let sevenDayPercent: Double?
        let contextUsedPercent: Double?
    }

    /// Percentages older than this are not shown. A rate-limit figure from
    /// yesterday is misinformation, not information.
    static let maxAge: TimeInterval = 30 * 60

    static var cacheURLs: [URL] {
        [
            ClaudeHome.root.appendingPathComponent("usage-menubar-cache.json"),
            ClaudeHome.root.appendingPathComponent("usage-toolbar-cache.json"),
        ]
    }

    /// Reads the freshest usable usage cache, or nil.
    static func usage(now: Date = Date()) -> UsageCache? {
        for url in cacheURLs {
            guard let data = try? Data(contentsOf: url),
                  let cache = try? JSONDecoder().decode(UsageCache.self, from: data),
                  isFresh(cache, now: now)
            else { continue }

            let hasAnything = cache.fiveHourPercent != nil
                || cache.sevenDayPercent != nil
                || cache.contextUsedPercent != nil
            if hasAnything { return cache }
        }
        return nil
    }

    /// Absolute difference, so a timestamp from the future is rejected too — a
    /// one-sided check treated any future-dated cache as eternally fresh.
    static func isFresh(_ cache: UsageCache, now: Date) -> Bool {
        guard let writtenAt = cache.writtenAt else { return true }
        return abs(now.timeIntervalSince1970 - writtenAt) <= maxAge
    }

    /// Turns a model id into something worth reading on a pet's forehead.
    /// Unknown ids are upper-cased rather than dropped, so a new model still
    /// displays instead of vanishing.
    /// The generations this formatter knows how to name.
    ///
    /// Hoisted out of `displayName` so it has a second reader: `FunFactTests`
    /// asserts that no fun fact names a generation, and points at THIS list to
    /// decide what a generation is. One source, so adding a future model
    /// automatically tightens the guard rather than leaving it stale — and the
    /// fact that this table has already had to grow is exactly the argument
    /// for the rule.
    static let knownModels: [(prefix: String, name: String)] = [
        ("claude-fable-5", "Fable 5"),
        ("claude-opus-5", "Opus 5"),
        ("claude-sonnet-5", "Sonnet 5"),
        ("claude-haiku-4-5", "Haiku 4.5"),
        ("claude-opus-4", "Opus 4"),
        ("claude-sonnet-4", "Sonnet 4"),
    ]

    public static func displayName(forModel id: String) -> String {
        if let match = knownModels.first(where: { id.hasPrefix($0.prefix) }) { return match.name }
        return id
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    /// What the ticker can say about a session right now.
    public struct Snapshot: Sendable, Equatable {
        public var model: String?
        public var branch: String?
        public var project: String?
        public var sessionCount: Int = 0
        public var activeHoursToday: Double?

        public init() {}
    }

    /// Every status line currently backed by real data. May be empty.
    ///
    /// Reads the usage cache from disk. Tests use the `usage:` overload with an
    /// explicit cache instead — the redline forbids tests touching the
    /// operator's `~/.claude/`, and a test that read it would pass or fail
    /// depending on whether their status line happened to be running.
    public static func lines(for snapshot: Snapshot, now: Date = Date()) -> [String] {
        lines(for: snapshot, usage: usage(now: now))
    }

    static func lines(for snapshot: Snapshot, usage cache: UsageCache?) -> [String] {
        var result: [String] = []

        if let model = snapshot.model {
            let name = displayName(forModel: model)
            if let context = cache?.contextUsedPercent {
                result.append("MODEL · \(name) @ \(Int(context.rounded()))% CONTEXT")
            } else {
                result.append("MODEL · \(name)")
            }
        }

        // These two are absent on most machines: Claude Code stopped publishing
        // rate limits to disk, and a percentage without a measured numerator is
        // a fabrication (Numerical Grounding). They light up on their own if the data
        // returns — that is the whole reason the cache is still read.
        if let fiveHour = cache?.fiveHourPercent {
            result.append("5-HOUR LIMIT @ \(Int(fiveHour.rounded()))%")
        }
        if let weekly = cache?.sevenDayPercent {
            result.append("WEEKLY USAGE @ \(Int(weekly.rounded()))%")
        }

        if snapshot.sessionCount > 1 {
            result.append("\(snapshot.sessionCount) SESSIONS LIVE")
        }

        if let hours = snapshot.activeHoursToday, hours >= 0.25 {
            result.append("CODING \(formatted(hours: hours)) TODAY")
        }

        if let project = snapshot.project {
            if let branch = snapshot.branch {
                result.append("\(project) · \(branch)")
            } else {
                result.append(project)
            }
        }

        return result
    }

    /// "45m" under an hour, "3.5h" above — a decimal of an hour reads as noise
    /// at small durations.
    static func formatted(hours: Double) -> String {
        if hours < 1 { return "\(Int((hours * 60).rounded()))m" }
        let rounded = (hours * 2).rounded() / 2
        return rounded == rounded.rounded()
            ? "\(Int(rounded))h"
            : String(format: "%.1fh", rounded)
    }
}
