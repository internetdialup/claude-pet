import Foundation

/// Persisted user settings.
///
/// Durability Honesty (`Bamboo.md` §3): every value here lands in the
/// `com.internetdialup.claude-pet` UserDefaults suite, which macOS backs with
/// `~/Library/Preferences/com.internetdialup.claude-pet.plist`. Any claim that
/// something "was saved" refers to that exact file.
@MainActor
public final class Preferences {
    public static let shared = Preferences()

    public static let suiteName = "com.internetdialup.claude-pet"
    private let store: UserDefaults

    private init() {
        store = UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    private enum Key {
        // v2: absolute screen coordinates. v1 stored a fraction of one screen's
        // visible frame, which could not express "on the other monitor".
        static let positionX = "pet.position.v2.x"
        static let positionY = "pet.position.v2.y"
        static let hasPosition = "pet.position.v2.set"
        static let soundsEnabled = "pet.sounds"
        static let toolBlipEnabled = "pet.sounds.toolBlip"
        static let notificationsEnabled = "pet.notifications"
        static let pinnedSession = "pet.pinnedSession"
        /// v3: became a Double for half-point sizes, then the default moved to
        /// 3.0. Bumped so stored values do not pin existing installs to the old
        /// default.
        static let scale = "pet.pixelSize.v3"
    }

    /// The window's bottom-left origin in global screen coordinates.
    ///
    /// Absolute rather than screen-relative: with several displays, a fraction
    /// is ambiguous about *which* screen it is a fraction of, and restoring one
    /// always dropped the pet back onto the main display. `PetWindowController`
    /// validates the restored point against the current screen arrangement.
    public var position: CGPoint? {
        get {
            guard store.bool(forKey: Key.hasPosition) else { return nil }
            return CGPoint(x: store.double(forKey: Key.positionX),
                           y: store.double(forKey: Key.positionY))
        }
        set {
            guard let newValue else {
                store.set(false, forKey: Key.hasPosition)
                return
            }
            store.set(newValue.x, forKey: Key.positionX)
            store.set(newValue.y, forKey: Key.positionY)
            store.set(true, forKey: Key.hasPosition)
        }
    }

    public var soundsEnabled: Bool {
        get { store.object(forKey: Key.soundsEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.soundsEnabled) }
    }

    /// Off by default — a blip on every tool call is a lot of tool calls.
    public var toolBlipEnabled: Bool {
        get { store.bool(forKey: Key.toolBlipEnabled) }
        set { store.set(newValue, forKey: Key.toolBlipEnabled) }
    }

    public var notificationsEnabled: Bool {
        get { store.object(forKey: Key.notificationsEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.notificationsEnabled) }
    }

    /// When set, the crab mirrors this session instead of the most recent one.
    public var pinnedSessionID: String? {
        get { store.string(forKey: Key.pinnedSession) }
        set { store.set(newValue, forKey: Key.pinnedSession) }
    }

    /// Points per sprite pixel. The 32×32 grid renders at 32× this.
    ///
    /// Claw'd occupies 24 grid cells across and 16 down, so the character
    /// measures `24 × pixelSize` by `16 × pixelSize` points. The default of 3.0
    /// puts him at 72×48pt, sized against the head of ChatGPT's desktop pet.
    ///
    /// Half-point steps are deliberate: on a 2× Retina display 3.0pt is exactly
    /// 6 device pixels per cell, so every sprite pixel stays the same physical
    /// size. A value like 3.2 would render some cells a device pixel wider than
    /// others, which is immediately visible in flat pixel art.
    public var pixelSize: Double {
        get {
            let stored = store.double(forKey: Key.scale)
            return Self.pixelSizes.contains(stored) ? stored : 3.0
        }
        set { store.set(newValue, forKey: Key.scale) }
    }

    public static let pixelSizes: [Double] = [2.5, 3, 3.5, 4, 5, 6, 8]

    /// The character's rendered size in points, for menu labels — the sprite
    /// frame includes transparent margin, so quoting the frame would overstate
    /// how big Claw'd actually looks.
    public static func characterSize(_ pixelSize: Double) -> CGSize {
        CGSize(width: 24 * pixelSize, height: 16 * pixelSize)
    }
}
