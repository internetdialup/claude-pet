import Foundation

/// 🌊 THE SURF SET — a swell rolls through, and he rides it.
///
/// Its own file rather than an arm of `HolidayAmbience` because it began as
/// something that file's header forbids — a lip curling in FRONT of him —
/// and kept the separate home after that turned out not to fit at this size.
/// See the note at the bottom for what was tried and why it was dropped.
///
/// It goes in before the body, and specifically before the yaw pass takes
/// its world snapshot: a wave that turned when the crab turned would be a
/// very strange sea.
enum SurfSet {

    /// Where the crest is, in columns, at `progress` 0…1.
    ///
    /// It enters off the right edge and leaves off the left, so the swell is
    /// never seen to begin or end — it arrives already travelling, the way
    /// water does. Off-grid at both bounds is also the no-snap defence: no
    /// cell has to appear from nothing.
    static func crest(at progress: Double) -> Double {
        38 - progress * 52
    }

    /// The water's surface row for a column, given the crest.
    ///
    /// A gaussian hump rather than a sine: a sine gives a swell a matching
    /// trough on both sides, and an ocean wave is a rise with flat water
    /// either side of it. The hump also decays to the flat line off-grid,
    /// which is why the entry and exit are invisible.
    /// How far the FLAT sea has risen, 0…1 — a separate envelope from the
    /// swell's.
    ///
    /// They were one number, and that was wrong twice over. A fixed sea
    /// popped a hundred and sixty cells of ocean into frame the instant the
    /// spell opened; tying the sea to the swell's slow envelope fixed the
    /// pop but meant there was no water at all for the first second — so
    /// the board appeared under a crab standing on nothing, and he looked,
    /// in the operator's words, like he was ollieing into the sea.
    ///
    /// Two envelopes solves both: the water floods in over the first beat
    /// and is already there when the board arrives, while the SWELL takes
    /// its time standing up and settling.
    static func sea(at progress: Double) -> Double {
        Ease.window(progress, duration: 1, edge: 0.07)
    }

    static func surface(_ x: Int, crest: Double, lift: Double, sea: Double) -> Int {
        let d = (Double(x) - crest) / 7.5
        let hump = exp(-d * d)
        // The flat line rides `sea` and only the hump rides `lift`.
        let flat = 32 - sea * 5
        return Int((flat - lift * 19 * hump).rounded())
    }

    /// How tall the swell stands, eased in and out across the spell so it
    /// builds and settles rather than arriving at full height.
    static func lift(at progress: Double) -> Double {
        Ease.window(progress, duration: 1, edge: 0.28)
    }

    /// The water behind him.
    ///
    /// Not a filled hump — the first cut was, and it read as a dark hill
    /// with a crab standing on it. A wave is a FACE: steep on its front,
    /// its crest overhanging, and hollow underneath where the lip has
    /// thrown out past the water below. So the fill stops short of the
    /// crest column on the leading side, and that gap is the tube.
    static func drawSwell(_ b: inout PixelBuffer, progress: Double) {
        let crest = crest(at: progress)
        let lift = lift(at: progress)
        let sea = sea(at: progress)
        guard sea > 0.01 else { return }
        for x in 0..<PixelBuffer.side {
            let top = surface(x, crest: crest, lift: lift, sea: sea)
            guard top < PixelBuffer.side else { continue }
            for y in max(0, top)..<PixelBuffer.side {
                // Two flat steps: a lit crown two rows deep and the body
                // beneath it. No ramp, the same rule the shell keeps.
                b.pixel(x, y, y < top + 2 ? .water : .waterDeep)
            }
            // Foam rides the STEEP part of the face, not the flat water on
            // either side of it: breaking is what makes foam, and flat sea
            // does not break. Its phase rides the crest so the speckle
            // travels with the wave instead of shimmering in place.
            let ahead = Double(x) - crest
            if abs(ahead) < 8, top >= 0, (x &+ Int(crest)) % 3 == 0 {
                b.pixel(x, top, .paper)
                if abs(ahead) < 4, top > 0 { b.pixel(x, top - 1, .paper) }
            }
        }
    }

    /// **What this file no longer does, and why it is worth recording.**
    ///
    /// It began as a barrel — a lip curling over him, the exception this
    /// file's header was written to justify. It did not fit. He is twenty
    /// cells of a thirty-two cell grid, so a tube around him needs about
    /// twenty-six and there is no version of that which is not "the frame
    /// fills with blue and the crab disappears". Every draft of the lip read
    /// as a diagonal streak across his face rather than as water passing in
    /// front of him.
    ///
    /// So the wave crests BEHIND him instead, and the exception is not
    /// spent: nothing here paints over the crab, and `HolidayAmbience`'s
    /// promise still holds for every effect in the app. The barrel is a
    /// good idea at a resolution this rig does not have.
}
