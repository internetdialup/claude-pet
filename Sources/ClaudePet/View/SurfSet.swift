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
    /// **Eased, not linear.** A crest crossing at a constant rate is a swell
    /// passing UNDER him — it lifts him and sets him down, which is what the
    /// first cut looked like. A wave that CARRIES him has to slow while it
    /// has him. The derivative here is `1 + carry·cos 2πp`: the crest rushes
    /// in, drops to 40% speed through the middle where he is riding it, and
    /// rushes out again.
    static let carry = 0.6
    static func crest(at progress: Double) -> Double {
        let eased = progress + carry * sin(2 * .pi * progress) / (2 * .pi)
        return 38 - eased * 52
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
        // ASYMMETRIC, which is the difference between a wave and a lump. A
        // swell is steep on the face it is breaking down and long on the back
        // it drags behind; a symmetric Gaussian is a hill, and at 32×32 it
        // read as one. The crest travels leftward, so the left side is the
        // face — five cells of falloff against the back's nine and a half.
        let dx = Double(x) - crest
        let d = dx / (dx < 0 ? faceWidth : backWidth)
        let hump = exp(-d * d)
        // The flat line rides `sea` and only the hump rides `lift`.
        let flat = 32 - sea * 5
        return Int((flat - lift * 19 * hump).rounded())
    }

    static let faceWidth = 5.0
    static let backWidth = 9.5

    /// How steep the water is at `x`, in cells per cell — signed, positive
    /// where the surface climbs to the right. His lean rides this rather than
    /// a threshold on the crest's position, so he tips with the face he is
    /// standing on instead of snapping between three attitudes.
    static func slope(at x: Int, crest: Double, lift: Double, sea: Double) -> Double {
        let left = surface(x - 2, crest: crest, lift: lift, sea: sea)
        let right = surface(x + 2, crest: crest, lift: lift, sea: sea)
        return Double(left - right) / 4
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
        // The water, with its surface kept so the foam and the spray can sit
        // ON it rather than each re-deriving where it is.
        var top = [Int](repeating: PixelBuffer.side, count: PixelBuffer.side)
        for x in 0..<PixelBuffer.side {
            let t = surface(x, crest: crest, lift: lift, sea: sea)
            top[x] = t
            guard t < PixelBuffer.side else { continue }
            for y in max(0, t)..<PixelBuffer.side {
                // Two flat steps: a lit crown two rows deep and the body
                // beneath it. No ramp, the same rule the shell keeps.
                b.pixel(x, y, y < t + 2 ? .water : .waterDeep)
            }
        }

        // 🌊 FOAM, weighted to the LIP. It used to be an even stipple eight
        // cells either side of the crest, which laid as much whitewater on
        // the smooth back of the wave as on the face that is breaking. Foam
        // runs DOWN a face: solid at the lip, thinning as it falls, and
        // nothing behind the crest at all. Its phase still rides the crest,
        // so the speckle travels with the wave rather than shimmering.
        for x in 0..<PixelBuffer.side {
            let t = top[x]
            guard t >= 0, t < PixelBuffer.side else { continue }
            let ahead = Double(x) - crest
            guard ahead < 2.5, ahead > -11 else { continue }
            let near = max(0, 1 - abs(ahead) / 11)
            let dense = near * near * lift
            let stipple = max(2, Int((4 - dense * 3).rounded()))
            guard abs(ahead) < 2.5 || (x &+ Int(crest)) % stipple == 0 else { continue }
            b.pixel(x, t, .paper)
            // A second row only where it is genuinely thick, so the lip
            // reads as a lip and the rest as scattered whitewater.
            if dense > 0.5, t > 0 { b.pixel(x, t - 1, .paper) }
        }

        drawSpray(&b, top: top, crest: crest, lift: lift)
    }

    /// Where he stands. Fixed, because he does not move across the grid —
    /// the wave moves under him.
    static let rider = 16

    /// 💦 Spray off the board, and the wake it leaves.
    ///
    /// Two ends of one idea: the board is tearing a line through water that
    /// is itself moving, so there is a burst where the tail bites and a
    /// trail where the water has already been torn. Without them he was a
    /// crab standing on a hill of blue — the wave had motion and he had none
    /// of it.
    ///
    /// The trail goes LEFT because that is where the water is going: the
    /// crest sweeps right to left, so anything thrown off is carried that
    /// way. A wake on the other side would be him water-skiing uphill.
    static func drawSpray(_ b: inout PixelBuffer, top: [Int],
                          crest: Double, lift: Double) {
        let here = top[rider]
        guard here > 0, here < PixelBuffer.side else { return }
        // How hard he is working: a bigger lift throws more water.
        let bite = min(1, lift * 1.1)
        guard bite > 0.15 else { return }

        // **Both start clear of him.** The first cut put the burst two cells
        // from his centre and the wake directly beneath, which is inside a
        // silhouette that runs from about x=10 to x=22 — the crab is drawn
        // after the water, so every cell of it was painted over and the
        // effect existed only in the buffer. Six cells out is where the
        // water is actually visible.
        // Seven, measured against his actual silhouette rather than guessed:
        // body and legs run about x=10 to x=22, so the first column where
        // water survives being drawn over is x=9.
        let clear = 7

        // The plume: water thrown UP behind him, rising and thinning. Above
        // the surface, not on it, or it reads as more foam.
        for step in 0...2 where bite > 0.25 + Double(step) * 0.22 {
            let x = rider - clear - step
            guard x >= 0, x < PixelBuffer.side else { continue }
            let y = top[x] - (2 - step)
            if y >= 0, y < PixelBuffer.side { b.pixel(x, y, .paper) }
        }

        // The wake: a trail downstream along the surface, coming apart as it
        // goes, starting where his legs stop hiding it.
        let length = min(9, Int((bite * 9).rounded()))
        guard length > 2 else { return }
        for step in clear...(length + clear) {
            let x = rider - step
            guard x >= 0 else { break }
            let y = top[x]
            guard y >= 0, y < PixelBuffer.side else { continue }
            if step <= clear + 1 || step % 2 == 0 { b.pixel(x, y, .paper) }
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
