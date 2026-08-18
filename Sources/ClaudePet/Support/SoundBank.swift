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
            return ([Note(frequency: 880, duration: 0.07),
                     Note(frequency: 1174, duration: 0.09)], 18)
        case .chime:
            return ([Note(frequency: 659, duration: 0.09),
                     Note(frequency: 988, duration: 0.14)], 18)
        case .blip:
            return ([Note(frequency: 523, duration: 0.04)], 18)
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
