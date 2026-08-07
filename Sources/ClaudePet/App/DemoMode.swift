import Foundation

/// Drives the pet through a scripted sequence of states, for recording.
///
/// Screen-recording the pet against *real* Claude activity means waiting for
/// whatever happens to occur and hoping the interesting states show up. This
/// makes a capture repeatable: the same sequence, the same timings, every run.
///
/// Enabled with `ClaudePet --demo`. It overrides the live feed entirely, so it
/// is only ever used for producing media.
@MainActor
enum DemoMode {

    /// One beat of the sequence.
    struct Beat {
        let mood: PetMood
        let bubble: String?
        let style: PetState.BubbleStyle
        let tool: String?
        let seconds: Double
        /// Runs the rainbow while this beat is on screen.
        var rainbow: Bool = false
    }

    /// Ordered so the reel builds: quiet, then thinking, then work, then the
    /// fire, then the payoff. `nudging` sits before `done` because it is the
    /// state people will not have seen before.
    static let script: [Beat] = [
        Beat(mood: .idle, bubble: "Let's build something awesome!", style: .plain, tool: nil, seconds: 3.0),
        Beat(mood: .thinking, bubble: "…", style: .dots, tool: nil, seconds: 2.5),
        Beat(mood: .working, bubble: "Wiring the activity pipeline", style: .plain, tool: "Bash", seconds: 3.0),
        Beat(mood: .cooking, bubble: "🔥", style: .plain, tool: nil, seconds: 3.0),
        Beat(mood: .nudging, bubble: "Plan's ready 👀", style: .plain, tool: nil, seconds: 3.0),
        Beat(mood: .done, bubble: "✅ 🥳 🎉", style: .plain, tool: nil, seconds: 2.5),
        Beat(mood: .idle, bubble: "MODEL · Opus 5", style: .marquee, tool: nil, seconds: 3.0),
        // Illustrative only. On a real machine this line stays hidden: Claude
        // Code no longer publishes rate limits to disk and the app refuses to
        // invent a percentage (see StatusTicker). The reel shows what the
        // feature looks like when the data is there.
        Beat(mood: .idle, bubble: "WEEKLY USAGE @ 25%", style: .marquee, tool: nil, seconds: 3.5),
        Beat(mood: .done, bubble: "🎉🪄", style: .plain, tool: nil, seconds: 4.0, rainbow: true),
    ]

    static var totalSeconds: Double { script.reduce(0) { $0 + $1.seconds } }

    /// Fabricated sessions for the roster.
    ///
    /// The roster lists session names, activities and project directories. In a
    /// recording destined for a public timeline those are the operator's real
    /// projects, so the demo substitutes invented ones — the panel still looks
    /// alive without publishing anything.
    static let sessions: [ClaudeSession] = {
        func make(_ name: String, _ project: String, _ activity: String, _ mood: PetMood) -> ClaudeSession {
            var session = ClaudeSession(id: name, pid: 1, name: name,
                                        cwd: "/Users/dev/Code/\(project)",
                                        procStart: "", startedAt: Date())
            session.mood = mood
            session.activity = activity
            session.branch = "main"
            return session
        }
        return [
            make("claude-pet-01", "claude-pet", "Wiring the activity pipeline", .working),
            make("pixel-rig-04", "pixel-rig", "Rendering the contact sheet", .thinking),
            make("hello-world-12", "hello-world", "Writing unit tests", .idle),
        ]
    }()

    /// The beat that should be showing `elapsed` seconds into the loop.
    static func beat(at elapsed: Double) -> Beat {
        var remaining = elapsed.truncatingRemainder(dividingBy: totalSeconds)
        for beat in script {
            if remaining < beat.seconds { return beat }
            remaining -= beat.seconds
        }
        return script[0]
    }

    static func state(at elapsed: Double, sessions: [ClaudeSession] = sessions) -> PetState {
        let beat = beat(at: elapsed)
        return PetState(mood: beat.mood,
                        bubble: beat.bubble,
                        tool: beat.tool,
                        sessions: sessions,
                        focusedSessionID: sessions.first?.id,
                        attentionCount: 0,
                        bubbleStyle: beat.style)
    }
}
