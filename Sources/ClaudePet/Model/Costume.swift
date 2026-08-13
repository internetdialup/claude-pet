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
    case wizard
    case astro
    case tuxedo

    /// The menu label.
    public var title: String {
        switch self {
        case .none: "Classic Claw'd"
        case .ninja: "Ninja"
        case .wizard: "Wizard"
        case .astro: "Astro"
        case .tuxedo: "Tuxedo"
        }
    }
}
