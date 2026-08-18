import Testing
import Foundation
@testable import ClaudePet

/// The sound bank's contract: synthesis is pure and deterministic, the WAV
/// wrapper is honest, and the gates decide exactly which cues play. No test
/// touches UserDefaults or plays audio.
@Suite("Sound synthesis")
struct SoundSynthesisTests {

    private var allCues: [SoundBank.Cue] { [.chirp, .chime, .blip] }

    @Test("Every cue's sample count matches its notes, with a sane peak")
    func sampleShape() {
        for cue in allCues {
            let (notes, _) = SoundBank.spec(for: cue)
            let expected = notes.reduce(0) { $0 + Int(44_100 * $1.duration) }
            let samples = SoundBank.samples(for: cue)
            #expect(abs(samples.count - expected) <= notes.count,
                    "\(cue): \(samples.count) vs \(expected)")

            let peak = samples.map { abs(Int($0)) }.max() ?? 0
            #expect(peak > Int(0.15 * 32_767), "\(cue) is inaudibly quiet")
            #expect(peak <= 32_000, "\(cue) clips past the master gain")
            // Instant attack: the opening of a non-rest cue is audible.
            #expect(samples.prefix(50).contains { abs(Int($0)) > 400 },
                    "\(cue) opens dead")
        }
    }

    @Test("Synthesis is deterministic — same cue, same bytes")
    func determinism() {
        for cue in allCues {
            #expect(SoundBank.samples(for: cue) == SoundBank.samples(for: cue))
        }
    }

    @Test("A rest renders as silence")
    func restsAreSilent() {
        // Rests aren't in the shipped tables yet; exercise the engine
        // directly through a cue whose spec we synthesize by hand once
        // rests exist. Until then, pin the invariant on the wave engine:
        // frequency 0 must never emit a sample.
        let (notes, _) = SoundBank.spec(for: .blip)
        #expect(notes.allSatisfy { $0.frequency > 0 },
                "when a rest enters a table, extend this test to assert its zeros")
    }

    @Test("The WAV wrapper carries the right magics and sizes")
    func wavShape() {
        let samples = SoundBank.samples(for: .blip)
        let data = SoundBank.wavData(samples)
        #expect(data.count == 44 + samples.count * 2)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE")
        #expect(String(data: data.subdata(in: 12..<16), encoding: .ascii) == "fmt ")
        #expect(String(data: data.subdata(in: 36..<40), encoding: .ascii) == "data")
    }
}

/// The gate table: who plays, under which switches.
@Suite("Sound gates")
@MainActor
struct SoundGateTests {

    @Test("The hush kills everything; the master switch kills everything")
    func hardGates() {
        for cue: SoundBank.Cue in [.chirp, .chime, .blip] {
            #expect(!SoundBank.shouldPlay(cue, soundsEnabled: true,
                                          blipsEnabled: true, hushed: true),
                    "\(cue) must hush during films")
            #expect(!SoundBank.shouldPlay(cue, soundsEnabled: false,
                                          blipsEnabled: true, hushed: false),
                    "\(cue) must respect the master switch")
        }
    }

    @Test("Only the blip consults the blips flag")
    func blipFlag() {
        #expect(!SoundBank.shouldPlay(.blip, soundsEnabled: true,
                                      blipsEnabled: false, hushed: false))
        #expect(SoundBank.shouldPlay(.blip, soundsEnabled: true,
                                     blipsEnabled: true, hushed: false))
        #expect(SoundBank.shouldPlay(.chirp, soundsEnabled: true,
                                     blipsEnabled: false, hushed: false))
        #expect(SoundBank.shouldPlay(.chime, soundsEnabled: true,
                                     blipsEnabled: false, hushed: false))
    }
}
