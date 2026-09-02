import SwiftUI
import AppKit

/// The GitHub service glyph, drawn from GitHub's actual mark instead of the
/// 8-bit stamp — the operator's call: "use the actual github svg."
///
/// **Live-only by construction**, the `CelebrationGlow` class of object: a
/// SwiftUI overlay in `PetRootView`'s composition, which the offline
/// renderers never compose — they render `CrabView`'s buffer directly, so no
/// committed byte can ever carry it. The pixel stamp underneath is suppressed
/// through `ServiceGlyph.pixelGlyph(for:vectorReady:)`, and if the asset ever
/// fails to load the suppression lifts and today's pixel glyph ships —
/// degradation, not a hole in the sky.
///
/// The bubble's little service badge stays pixel on purpose: it reads
/// `PetState.serviceGlyph` down a different plumbing line and is bubble
/// furniture, not the floating mark.
///
/// Composition matches the pixel read — a rounded `slateSoft` tile with the
/// mark in `kraft` — so the swap reads as "the same badge, HD" rather than a
/// new object. It rides the SAME `Ease.amount` envelope over the same latch
/// timestamps `CrabView` uses for the pixel glyph, so entrance and exit stay
/// in step with every other appearance in the app.
struct VectorServiceGlyph: View {
    let shownAt: Double?
    let endedAt: Double?
    let pixelSize: Double

    /// GitHub's mark, loaded once from the resource bundle as a template —
    /// only its alpha is used, the tint is ours. macOS decodes SVG natively
    /// in `NSImage` on the app's macOS 14 floor. nil (missing bundle, failed
    /// decode) means the vector glyph never engages.
    static let githubMark: NSImage? = {
        guard let url = ResourceBundle.resolved?.url(forResource: "github-mark",
                                                     withExtension: "svg"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Whether the vector path is ready — the one fact the suppression seam
    /// needs.
    static var available: Bool { githubMark != nil }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let amount = Ease.amount(now: now, since: shownAt, endedAt: endedAt)
            if amount > 0.001, let mark = Self.githubMark {
                let side = 8 * pixelSize
                RoundedRectangle(cornerRadius: pixelSize, style: .continuous)
                    .fill(Palette.slateSoft)
                    .frame(width: side, height: side)
                    .overlay {
                        Image(nsImage: mark)
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .scaledToFit()
                            .foregroundStyle(Palette.kraft)
                            .padding(0.75 * pixelSize)
                    }
                    // The glyph box: cols 1–8, rows 0–7 of the sprite grid.
                    .offset(x: pixelSize, y: 0)
                    .opacity(amount)
            }
        }
    }
}
