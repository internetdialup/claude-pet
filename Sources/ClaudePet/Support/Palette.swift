import SwiftUI

/// Claw'd's palette, taken from the official sticker art.
///
/// The defining property is that it is **flat**. Claw'd has no gradients, no
/// shading ramp, and no outline — solid terracotta, solid black eyes, solid
/// white mouth. Adding depth to him is the single easiest way to make him stop
/// looking like himself.
public enum Palette {
    public static let body = Color(hex: 0xCE7B5C)        // Claw'd terracotta
    public static let ink = Color(hex: 0x000000)         // eyes
    public static let white = Color(hex: 0xFFFFFF)       // mouth
    public static let screenDark = Color(hex: 0x2E3A87)  // terminal window body
    public static let screenLight = Color(hex: 0x4756B8) // terminal title bar
    public static let green = Color(hex: 0x3FA34D)       // done / check badge
    public static let yellow = Color(hex: 0xE8B84B)      // sparkles
    public static let pink = Color(hex: 0xE86A9A)        // alert
    public static let sky = Color(hex: 0x6A9BCC)         // thinking accent
    public static let steel = Color(hex: 0x8A8F98)       // wrench, screwdriver
    public static let flame = Color(hex: 0xE8712F)       // flame body
    /// The existing `yellow` is a muted gold; a flame core needs to read hot.
    public static let flameCore = Color(hex: 0xF7D046)   // hottest part of the burst
    public static let ember = Color(hex: 0xC4451F)       // deep outer licks

    /// The cooking heat bands: two flat stops between the terracotta shell and
    /// the flame, so the cascade is quantised bands — never a gradient, which
    /// the rule at the top of this file bans.
    public static let bodyHot = Color(hex: 0xDE8A45)
    public static let bodyEmber = Color(hex: 0xD65B31)

    /// Chrome colours for the bubble and roster (not part of the sprite).
    public static let slate = Color(hex: 0x141413)
    public static let slateSoft = Color(hex: 0x3D3D3A)
    public static let kraft = Color(hex: 0xF0EEE6)
    public static let alert = Color(hex: 0xE05252)

    /// Accent for a given mood. Defined once in `MoodStyle`.
    public static func accent(for mood: PetMood) -> Color { mood.style.accent }

    /// The backdrop the composed marketing scenes stand on.
    ///
    /// **Provenance.** These were derived by sampling a local macOS aerial
    /// wallpaper thumbnail for *hue and saturation only* — the whole image sits
    /// in a 186–262° band with a mean of 202°. No pixel of that image is used
    /// or redistributed here; it is copyrighted video, and this is five hex
    /// values arrived at by measurement.
    ///
    /// **Why the lightness moved.** The sampled mid-water was `#3F98C3`, whose
    /// relative luminance is 0.292 against `body`'s 0.281 — a contrast ratio of
    /// **1.02:1**. Identical brightness at a near-complementary hue is the
    /// recipe for chromatic vibration, and it shatters under GIF's 256-colour
    /// quantisation. `green` (0.278), `pink` (0.298) and `flame` (0.292) collide
    /// the same way. Keeping the hue and dropping the lightness to 8–29% puts
    /// Claw'd at 5.2:1 where he actually stands.
    ///
    /// **Why it is banded rather than a gradient.** Measured on the real
    /// `working.gif` frames, a smooth ramp costs 1.79× the transparent baseline
    /// and four flat bands cost 1.41×. Banding is also the only option
    /// consistent with the rule at the top of this file: flat colour, no
    /// shading ramp. `PaletteContrastTests` pins every ratio quoted here.
    public enum Ocean {
        /// Surface → abyss. Claw'd stands on the lower third, so the *dark* end
        /// is at the bottom — the inverse of the usual instinct, and what puts
        /// the most separation behind the character.
        public static let surface = Color(hex: 0x1C5678)
        public static let shelf = Color(hex: 0x16445F)
        public static let mid = Color(hex: 0x103346)
        public static let deep = Color(hex: 0x0B212D)
        public static let abyss = Color(hex: 0x081821)

        /// A thin caustic in the top 8% of the frame. The one stop taken from
        /// the aerial unmodified, because foam has no contrast job to do.
        public static let foam = Color(hex: 0xC5D7E2)

        /// Surface first. The backdrop renders exactly these and nothing between
        /// them, so the encoded colour table holds `ramp.count` entries.
        public static let ramp: [Color] = [surface, shelf, mid, deep, abyss]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
