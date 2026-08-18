import AppKit

/// Short synthesised cues. No audio assets ship with the app — samples are
/// generated in memory at first use and handed to `NSSound(data:)`, which
/// keeps `Package.swift` resource-free, the bundle honest about having no
/// binary blobs, and the disk untouched.
///
/// The synthesis is pure and testable: `samples(for:)` → `wavData(_:)` are
/// nonisolated static functions of the cue tables alone — same input, same
/// bytes, no clocks, no randomness (the noise wave is a splitmix64 hash of
/// the sample index).
@MainActor
public enum SoundBank {

    // MARK: - The vocabulary

    public enum Wave: Sendable { case sine, square, triangle, noise }

    /// One note of a cue. `frequency` 0 is a rest; `slideTo` glides the
    /// pitch exponentially across the note — the squeal's whole trick.
    public struct Note: Sendable {
        var frequency: Double
        var duration: Double
        var wave: Wave = .sine
        var level: Double = 1.0
        var slideTo: Double? = nil
    }

    public enum Cue: Hashable {
        case chirp, chime, blip
        /// The poke squeal — `step` 1…3 rises so a triple-poke reads as a
        /// combo climbing into the party.
        case squeal(step: Int)
        case pounce, purr, shimmer, ignition, fanfare
    }

    // MARK: - The gates

    /// The film hush, injected by AppDelegate at launch: sound cues hush
    /// during films whether or not he steps aside for them — the CHANGELOG's
    /// standing promise, enforced HERE so every cue from every seam honors
    /// it without threading pet state around.
    ///
    /// (An older gate checked `frontmostApplication?.activationPolicy ==
    /// .prohibited` claiming fullscreen/DND detection — it detected neither;
    /// a prohibited frontmost app is a background agent, near-impossible in
    /// practice. The film watch is the real mechanism, so that gate is gone.)
    public static var isHushed: () -> Bool = { false }

    /// Pure decision: which cues play under which switches.
    static func shouldPlay(_ cue: Cue, soundsEnabled: Bool,
                           blipsEnabled: Bool, hushed: Bool) -> Bool {
        guard soundsEnabled, !hushed else { return false }
        if case .blip = cue { return blipsEnabled }
        return true
    }

    // MARK: - Playback

    private static var cache: [Cue: NSSound] = [:]

    public static func play(_ cue: Cue) {
        guard shouldPlay(cue,
                         soundsEnabled: Preferences.shared.soundsEnabled,
                         blipsEnabled: Preferences.shared.toolBlipEnabled,
                         hushed: isHushed()) else { return }

        if let cached = cache[cue] {
            cached.stop()
            cached.play()
            return
        }
        guard let sound = NSSound(data: wavData(samples(for: cue))) else { return }
        sound.volume = 0.35
        cache[cue] = sound
        sound.play()
    }

    // MARK: - The cue tables

    /// The notes and the envelope's decay rate. The envelope resets per
    /// note but decays at the CUE's rate, so a slow-decay finale can ring
    /// while a blip stays a blip. Nonisolated: a pure table.
    nonisolated static func spec(for cue: Cue) -> (notes: [Note], decay: Double) {
        switch cue {
        case .chirp:
            // The "hey!": the same rising skeleton, square-voiced.
            return ([Note(frequency: 880, duration: 0.06, wave: .square, level: 0.5),
                     Note(frequency: 1174.7, duration: 0.09, wave: .square, level: 0.55)], 16)
        case .chime:
            // The done bell: E5-B5-E6 soft triangle arpeggio.
            return ([Note(frequency: 659.3, duration: 0.08, wave: .triangle, level: 0.5),
                     Note(frequency: 987.8, duration: 0.09, wave: .triangle, level: 0.5),
                     Note(frequency: 1318.5, duration: 0.14, wave: .triangle, level: 0.55)], 12)
        case .blip:
            return ([Note(frequency: 523, duration: 0.04, wave: .square, level: 0.45)], 18)
        case .squeal(let step):
            // "Wheee!" — a fast pitch-bend up and a tip, two semitones
            // higher per step. CUTE is the spec.
            let ratio = pow(2.0, Double(max(1, min(3, step)) - 1) * 2.0 / 12.0)
            return ([Note(frequency: 620 * ratio, duration: 0.15, wave: .square,
                          level: 0.5 + 0.025 * Double(step), slideTo: 1500 * ratio),
                     Note(frequency: 1975.5 * ratio, duration: 0.04, wave: .square, level: 0.4)], 10)
        case .pounce:
            // Squeak-squeak — the bug never stood a chance.
            return ([Note(frequency: 1400, duration: 0.07, wave: .square, level: 0.35, slideTo: 2000),
                     Note(frequency: 0, duration: 0.02),
                     Note(frequency: 2200, duration: 0.05, wave: .square, level: 0.3)], 12)
        case .purr:
            // A low triangle wobble, one-shot on pet-start.
            return ((0..<8).map { beat in
                Note(frequency: beat % 2 == 0 ? 82 : 98, duration: 0.07,
                     wave: .triangle, level: beat % 2 == 0 ? 0.45 : 0.4)
            }, 3)
        case .shimmer:
            // The wardrobe sparkle: an ascending five-note triangle run.
            return ([Note(frequency: 1046.5, duration: 0.045, wave: .triangle, level: 0.4),
                     Note(frequency: 1318.5, duration: 0.045, wave: .triangle, level: 0.4),
                     Note(frequency: 1568.0, duration: 0.045, wave: .triangle, level: 0.4),
                     Note(frequency: 1975.5, duration: 0.045, wave: .triangle, level: 0.45),
                     Note(frequency: 2637.0, duration: 0.06, wave: .triangle, level: 0.5)], 10)
        case .ignition:
            // The fwoosh: a noise burst, a rising flame, a crackle of embers.
            return ([Note(frequency: 1, duration: 0.07, wave: .noise, level: 0.6),
                     Note(frequency: 140, duration: 0.18, wave: .square, level: 0.5, slideTo: 560),
                     Note(frequency: 1, duration: 0.10, wave: .noise, level: 0.25)], 9)
        case .fanfare:
            // The epic landing: G4-C5-E5-G5, a breath, E5-G5-C6 — and the
            // last note rides the slow decay all the way out. ~1.29s.
            return ([Note(frequency: 392.0, duration: 0.11, wave: .square, level: 0.5),
                     Note(frequency: 523.25, duration: 0.11, wave: .square, level: 0.5),
                     Note(frequency: 659.26, duration: 0.11, wave: .square, level: 0.5),
                     Note(frequency: 784.0, duration: 0.22, wave: .square, level: 0.55),
                     Note(frequency: 0, duration: 0.06),
                     Note(frequency: 659.26, duration: 0.09, wave: .square, level: 0.45),
                     Note(frequency: 784.0, duration: 0.09, wave: .square, level: 0.5),
                     Note(frequency: 1046.5, duration: 0.5, wave: .square, level: 0.6)], 5)
        }
    }

    // MARK: - Synthesis (pure)

    nonisolated static func samples(for cue: Cue, sampleRate: Double = 44_100) -> [Int16] {
        let (notes, decay) = spec(for: cue)
        var out: [Int16] = []
        for note in notes {
            let count = Int(sampleRate * note.duration)
            guard note.frequency > 0 else {
                out.append(contentsOf: repeatElement(0, count: count))
                continue
            }
            var phase = 0.0
            for index in 0..<count {
                let t = Double(index) / sampleRate
                // Exponential pitch glide: f(t) = f0 · (f1/f0)^(t/dur).
                let frequency: Double
                if let target = note.slideTo {
                    frequency = note.frequency * pow(target / note.frequency, t / note.duration)
                } else {
                    frequency = note.frequency
                }
                phase += frequency / sampleRate
                let cycle = phase.truncatingRemainder(dividingBy: 1)
                let raw: Double
                switch note.wave {
                case .sine: raw = sin(2 * .pi * cycle)
                case .square: raw = cycle < 0.5 ? 1 : -1
                case .triangle: raw = 4 * abs(cycle - 0.5) - 1
                case .noise:
                    // splitmix64 over the sample index — deterministic hiss.
                    var v = UInt64(index) &* 0x9E37_79B9_7F4A_7C15
                    v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
                    v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
                    raw = Double(v >> 11) / Double(1 << 53) * 2 - 1
                }
                // Percussive envelope: instant attack, per-note reset, the
                // cue's own decay. A raw wave with hard edges clicks.
                let envelope = exp(-t * decay)
                let value = raw * envelope * 0.6 * note.level
                out.append(Int16(max(-1, min(1, value)) * 32_000))
            }
        }
        return out
    }

    /// A minimal mono 16-bit WAV wrapper around the samples.
    nonisolated static func wavData(_ samples: [Int16], sampleRate: Double = 44_100) -> Data {
        var data = Data()
        let byteCount = samples.count * 2
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                    // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        for sample in samples { append(sample) }
        return data
    }

}
