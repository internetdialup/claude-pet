import Foundation

/// A costume the operator picks and keeps.
///
/// **Not a `Prop`.** A prop is a status signal the animator chooses for you — a
/// terminal while a run is going, a check when the work lands — and it changes
/// several times a minute. A costume is a wardrobe choice: it survives every
/// mood change and every prop swap, and status always outranks wardrobe — the
/// rainbow party, the fire tint and the heat bands all paint over costume
/// colours, never the other way round.
///
/// Lives in the Model layer with no SwiftUI import, because `Preferences`
/// persists it and `Preferences` is Foundation-only.
///
/// **Adding one touches exactly two more places, and the compiler names both:**
/// `CostumeStyle.of` and `CrabCostume.draw`, switches written deliberately
/// without a `default:` clause.
public enum Costume: String, Sendable, CaseIterable, Codable {
    case none
    case ninja
    // Wizard, astro and tuxedo were tried and retired in v1.4.0 — "default
    // is dope, ninja is dope." Their raw values fall back to Classic on
    // decode, so a stored preference cannot strand anyone.
    case retroBlack
    case matrix
    case tiger
    case white
    case gundam
    case sonic
    case frankenstein
    case arcade
    // Appended (dissolve seeds are allCases indices — order is load-bearing):
    // the seasonal wardrobe. Each is menu-listed only inside its holiday's
    // window (`isAvailable(on:)` in Holiday.swift), but RENDERS everywhere —
    // the montage, the sampler and the tests draw them date-free. Old builds
    // decode the unknown raw values to Classic via the existing fallback.
    case pumpkin
    case turkey
    case santa
    // Appended: the skater fit — evergreen, unlike the three above it.
    case skater

    /// The menu label.
    public var title: String {
        switch self {
        case .none: "Classic Claw'd"
        case .ninja: "Ninja"
        case .retroBlack: "Retro Black"
        // Retitled from "Matrix" on the operator's call — same raw value,
        // same stored prefs, the look just grew glasses and a day job.
        case .matrix: "Coder"
        case .tiger: "Tiger"
        case .white: "Arctic White"
        case .gundam: "Gundam"
        case .sonic: "Sonic"
        case .frankenstein: "Frankenstein"
        case .arcade: "Arcade"
        case .pumpkin: "🎃 Jack-o'-Lantern"
        case .turkey: "🦃 Turkey"
        case .santa: "🎅 Santa"
        case .skater: "🛹 Skater"
        }
    }
}
