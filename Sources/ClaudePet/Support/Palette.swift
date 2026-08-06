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
    public static let flame = Color(hex: 0xE8712F)       // rocket exhaust

    /// Chrome colours for the bubble and roster (not part of the sprite).
    public static let slate = Color(hex: 0x141413)
    public static let slateSoft = Color(hex: 0x3D3D3A)
    public static let kraft = Color(hex: 0xF0EEE6)
    public static let alert = Color(hex: 0xE05252)

    /// Accent for a given mood — used by the bubble border and the status dot.
    public static func accent(for mood: PetMood) -> Color {
        switch mood {
        case .idle: body
        case .thinking: sky
        case .working: screenLight
        case .done: green
        case .needsAttention: alert
        case .sleeping: slateSoft
        }
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
