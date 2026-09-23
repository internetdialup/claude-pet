import Testing
import Foundation
@testable import ClaudePet

/// **Every line a renderer puts in his mouth is one he can really say.**
///
/// The review and marketing renderers hard-code their bubbles, and the
/// September 2026 fact re-cut rewrote the deck underneath them. Nine of ten
/// sampler and comp-board lines went on quoting facts the pet no longer says —
/// one of them the temperature line that same round had retired as decayed —
/// and nothing failed, because nothing checked. The verification runbook's
/// gate F8 did check, as a frozen list of strings, and went stale the same day.
///
/// So this checks MEMBERSHIP, not text: each line must be in the set of lines
/// the pet can actually say, or sit in `allowlist` with a reason for being
/// there. A deck edit that strands a quote now fails here, by name, instead of
/// shipping in a sample.
@MainActor
struct SayableLinesTests {

    /// Everything he can say: facts, tips, every occasion pool, every
    /// task-matched rule, and every costume's skate deck.
    static var sayable: Set<String> {
        var lines = Set(FunFacts.all)
        lines.formUnion(ClaudeTips.all)
        for pool in Vocab.catalogue.values { lines.formUnion(pool) }
        for rule in Vocab.rules { lines.formUnion(rule.lines) }
        for costume in Costume.allCases { lines.formUnion(Vocab.skateLines(for: costume)) }
        return lines
    }

    /// Lines that are deliberately NOT pool lines, each with the reason. Every
    /// entry must still be in use — `theAllowlistIsNotStale` — so this cannot
    /// quietly become the place retired lines go to hide.
    static let allowlist: [String: String] = [
        "Johnny Tsunami once said — Go Big or Go Home 🤙":
            "a campaign line; CostumeSampler.soloShouts keeps it out of vocab on purpose",
        "…": "the thinking bubble's dots — a style, not a line",
        "Wiring the pipeline": "stands in for task text, which is the operator's own words",
        "MODEL · Opus 5": "a status-ticker readout, not speech",
        "WEEKLY USAGE @ 25%": "a status-ticker readout, marked illustrative in DemoMode",
        "🎉🪄": "the reel's party beat is illustration — the live party shows no bubble",
    ]

    /// Every hard-coded bubble in the renderers, with where it lives.
    ///
    /// `SizzleScript` is absent on purpose: its own header says "The words (all
    /// fabricated)", and its bubbles are tool and task text rather than lines
    /// the pet speaks. `everyBubbleIsInventoried` still counts its call sites.
    static var inventory: [(source: String, line: String)] {
        var lines: [(source: String, line: String)] = []
        for member in CostumeSampler.cast { lines.append(("CostumeSampler.cast", member.line)) }
        for shout in CostumeSampler.soloShouts { lines.append(("CostumeSampler.soloShouts", shout.line)) }
        lines.append(("CompBoard.fact", CompBoard.fact))
        for member in ReelRenderer.costumeCast {
            if let line = member.line { lines.append(("ReelRenderer.costumeCast", line)) }
        }
        for pick in ReelRenderer.factPicks { lines.append(("ReelRenderer.factPicks", pick.text)) }
        for member in PaletteTricks.bubbleCast { lines.append(("PaletteTricks.bubbleCast", member.line)) }
        lines.append(("SketchScene.Layer default", SketchScene.Layer(kind: .bubble).text))
        for beat in DemoMode.script {
            if let line = beat.bubble { lines.append(("DemoMode.script", line)) }
        }
        for beat in DemoMode.reelScript {
            if let line = beat.bubble { lines.append(("DemoMode.reelScript", line)) }
        }
        return lines
    }

    @Test("every line a renderer quotes is one he can really say")
    func everyQuotedLineIsSayable() {
        let sayable = Self.sayable
        for (source, line) in Self.inventory where Self.allowlist[line] == nil {
            #expect(sayable.contains(line),
                    "\(source) quotes \"\(line)\", which is in no pool — he never says it")
        }
    }

    @Test("every allowlisted line is still in use")
    func theAllowlistIsNotStale() {
        let used = Set(Self.inventory.map(\.line))
        for (line, why) in Self.allowlist {
            #expect(used.contains(line),
                    "\"\(line)\" is allowlisted (\(why)) but nothing uses it any more — remove it")
        }
    }

    /// The coms-bridge, for bubbles. The inventory above is kept by hand, and a
    /// hand-kept inventory is exactly what went stale the last time — so this
    /// counts `ThoughtBubble(text:` call sites per file under `App/` (code
    /// lines only). A new renderer with its own bubble moves the count, and the
    /// failure says to add its lines to `inventory` or `allowlist` first.
    @Test("no renderer grows a bubble the inventory doesn't know about")
    func everyBubbleIsInventoried() throws {
        let known: [String: Int] = [
            "CompBoard.swift": 1,
            "CostumeSampler.swift": 2,
            "PaletteTricks.swift": 1,
            "ReelRenderer.swift": 7,
            "SizzleRenderer.swift": 4,
        ]
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClaudePet/App")
        var found: [String: Int] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: app.path)
        where name.hasSuffix(".swift") {
            let source = try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)
            let sites = source.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .reduce(0) { $0 + $1.components(separatedBy: "ThoughtBubble(text:").count - 1 }
            if sites > 0 { found[name] = sites }
        }
        let note = "bubble call sites are \(found.sorted { $0.key < $1.key }) — add any new "
            + "bubble's lines to SayableLinesTests.inventory or allowlist, then update `known`"
        #expect(found == known, "\(note)")
    }
}
