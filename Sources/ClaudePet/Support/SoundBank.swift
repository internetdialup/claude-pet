import AppKit

/// Short synthesised cues. No audio assets ship with the app — the tones are
/// generated once at first use, which keeps `Package.swift` resource-free and the
/// bundle honest about having no binary blobs.
@MainActor
public enum SoundBank {
    public enum Cue { case chirp, chime, blip }

    private static var cache: [String: NSSound] = [:]

    public static func play(_ cue: Cue) {
        guard Preferences.shared.soundsEnabled else { return }
        if cue == .blip && !Preferences.shared.toolBlipEnabled { return }

        // Don't chirp over a fullscreen presentation or Do Not Disturb.
        if NSWorkspace.shared.frontmostApplication?.activationPolicy == .prohibited { return }

        let key: String
        let tones: [(frequency: Double, duration: Double)]
        switch cue {
        case .chirp:  key = "chirp";  tones = [(880, 0.07), (1174, 0.09)]
        case .chime:  key = "chime";  tones = [(659, 0.09), (988, 0.14)]
        case .blip:   key = "blip";   tones = [(523, 0.04)]
        }

        if let cached = cache[key] {
            cached.stop()
            cached.play()
            return
        }
        guard let url = synthesize(tones: tones, name: key),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        sound.volume = 0.35
        cache[key] = sound
        sound.play()
    }

    /// Writes a small mono 16-bit WAV into the app's caches directory.
    /// Path: `~/Library/Caches/com.internetdialup.claude-pet/<name>.wav`.
    private static func synthesize(tones: [(frequency: Double, duration: Double)], name: String) -> URL? {
        let sampleRate = 44_100.0
        var samples: [Int16] = []

        for tone in tones {
            let count = Int(sampleRate * tone.duration)
            for index in 0..<count {
                let t = Double(index) / sampleRate
                // Percussive envelope: instant attack, exponential decay. A raw
                // sine with hard edges clicks.
                let envelope = exp(-t * 18)
                let value = sin(2 * .pi * tone.frequency * t) * envelope * 0.6
                samples.append(Int16(max(-1, min(1, value)) * 32_000))
            }
        }

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

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Preferences.suiteName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).wav")
        do { try data.write(to: url) } catch { return nil }
        return url
    }
}
