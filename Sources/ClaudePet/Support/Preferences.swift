import Foundation

/// Persisted user settings.
///
/// Durability Honesty: every value here lands in the
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
        static let cookingNotifications = "pet.notifications.cooking"
        static let pinnedSession = "pet.pinnedSession"
        /// v3: became a Double for half-point sizes, then the default moved to
        /// 3.0. Bumped so stored values do not pin existing installs to the old
        /// default.
        static let scale = "pet.pixelSize.v3"
        static let costume = "pet.costume"
        static let stepsAsideForVideo = "pet.video.stepsAside"
        static let persistency = "pet.persistency"
        // The second pet's own slice. Pet 1's keys stay exactly as they are —
        // a summoned sibling must not move anyone's saved home.
        static let pet2Enabled = "pet2.enabled"
        static let pet2Costume = "pet2.costume"
        static let pet2PinnedSession = "pet2.pinnedSession"
        static let pet2PositionX = "pet2.position.v2.x"
        static let pet2PositionY = "pet2.position.v2.y"
        static let pet2HasPosition = "pet2.position.v2.set"
    }

    /// Whether the second pet is summoned, surviving relaunches.
    public var pet2Enabled: Bool {
        get { store.bool(forKey: Key.pet2Enabled) }
        set { store.set(newValue, forKey: Key.pet2Enabled) }
    }

    /// The second pet's wardrobe, by raw value with the same unknown-string
    /// fallback as pet 1's.
    public var pet2Costume: Costume {
        get { store.string(forKey: Key.pet2Costume).flatMap(Costume.init(rawValue:)) ?? .none }
        set { store.set(newValue.rawValue, forKey: Key.pet2Costume) }
    }

    /// The session the second pet follows, or nil for "busiest that pet 1
    /// isn't showing".
    public var pet2PinnedSessionID: String? {
        get { store.string(forKey: Key.pet2PinnedSession) }
        set { store.set(newValue, forKey: Key.pet2PinnedSession) }
    }

    /// The second pet's saved home — same absolute-coordinates rationale as
    /// pet 1's `position`.
    public var pet2Position: CGPoint? {
        get {
            guard store.bool(forKey: Key.pet2HasPosition) else { return nil }
            return CGPoint(x: store.double(forKey: Key.pet2PositionX),
                           y: store.double(forKey: Key.pet2PositionY))
        }
        set {
            guard let newValue else {
                store.set(false, forKey: Key.pet2HasPosition)
                return
            }
            store.set(newValue.x, forKey: Key.pet2PositionX)
            store.set(newValue.y, forKey: Key.pet2PositionY)
            store.set(true, forKey: Key.pet2HasPosition)
        }
    }

    /// Whether he floats above every window (the classic desktop-pet posture)
    /// or sits at normal window level, where opening Finder or a browser
    /// covers him and nothing ever shuffles him forward.
    ///
    /// ON by default — floating is what the pet has always done, and the
    /// toggle exists for the operator who wants him ambient rather than
    /// omnipresent. Independent of the film step-aside: that gates an alpha
    /// fade, this gates a window level, and they never touch each other's
    /// property.
    public var persistent: Bool {
        get { store.object(forKey: Key.persistency) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.persistency) }
    }

    /// Whether he gets out of the way of a fullscreen film on his own display.
    ///
    /// **ON by default**, because the asymmetry runs one way: wrongly absent is
    /// a politely missing pet you can bring back with one menu row; wrongly
    /// present is a crab sitting on top of something you may be presenting
    /// from, in front of people. A default that ships off is a feature nobody
    /// discovers until after the meeting it would have helped.
    ///
    /// This gates what is DONE with the film answer, never whether the
    /// question is asked — `FilmWatch` runs regardless, because sound cues are
    /// suppressed during films whether or not he steps aside for them.
    public var stepsAsideForVideo: Bool {
        get { store.object(forKey: Key.stepsAsideForVideo) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.stepsAsideForVideo) }
    }

    /// The costume he is wearing.
    ///
    /// Stored by `rawValue` rather than by ordinal, so reordering the enum or
    /// removing a case cannot silently dress him as something else. An unknown
    /// string — a costume that existed in a newer build — falls back to `.none`
    /// rather than trapping.
    public var costume: Costume {
        get { store.string(forKey: Key.costume).flatMap(Costume.init(rawValue:)) ?? .none }
        set { store.set(newValue.rawValue, forKey: Key.costume) }
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

    /// Off by default: cooking starts often, and a banner every time would be
    /// the kind of notification people turn off entirely.
    public var cookingNotificationsEnabled: Bool {
        get { store.bool(forKey: Key.cookingNotifications) }
        set { store.set(newValue, forKey: Key.cookingNotifications) }
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
