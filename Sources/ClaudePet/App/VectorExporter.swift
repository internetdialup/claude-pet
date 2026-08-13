import Foundation

/// Emits Claw'd as editable vector pixels: one SVG for the base body, and one
/// per prop as an overlay layer that stacks on the base. This is the code →
/// design bridge — the SVGs import into Figma as components the operator can
/// eyeball and annotate, while the Swift rig stays the source of truth.
///
/// Shape: `viewBox 0 0 32 32` at 10× display size, `crispEdges`, one `<g>` per
/// ink holding one `<rect>` per horizontal run — the same run-compaction the
/// live renderer draws with, so the vector output is structurally the sprite.
enum VectorExporter {

    /// Writes `clawd-base.svg` plus `clawd-prop-<name>.svg` for every prop.
    /// Returns false (and says why) rather than trapping — exit codes are the
    /// evidence.
    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            print("could not create \(directory): \(error.localizedDescription)")
            return false
        }

        let base = CrabRig.render(CrabPose())
        var wrote = 0

        guard write(svg(for: base), to: root.appendingPathComponent("clawd-base.svg")) else { return false }
        wrote += 1

        for prop in CrabPose.Prop.allCases where prop != .none {
            var pose = CrabPose()
            pose.prop = prop
            // The same showcase phase the contact sheet's prop strip uses, so
            // the vectors match the committed reference art.
            pose.propPhase = 0.4
            let posed = CrabRig.render(pose)

            // The overlay is the diff against the base. A prop may add cells or
            // repaint body cells (the worn ones do); it can never erase — if
            // one ever does, an overlay cannot express it, so fall back to a
            // full-pose export and say so.
            var overlay = PixelBuffer()
            var erasesBase = false
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where posed[x, y] != base[x, y] {
                    if posed[x, y] == .clear { erasesBase = true }
                    overlay[x, y] = posed[x, y]
                }
            }

            let name = "clawd-prop-\(prop.rawValue).svg"
            let subject = erasesBase ? posed : overlay
            if erasesBase { print("note: \(prop.rawValue) erases base cells; exported as a full pose") }
            guard write(svg(for: subject), to: root.appendingPathComponent(name)) else { return false }
            wrote += 1
        }

        print("wrote \(wrote) SVGs to \(root.path)")
        return true
    }

    private static func write(_ contents: String, to url: URL) -> Bool {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("could not write \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - SVG

    static func svg(for buffer: PixelBuffer) -> String {
        var groups: [PixelBuffer.Ink: [String]] = [:]
        for run in buffer.runs() {
            groups[run.ink, default: []]
                .append(#"    <rect x="\#(run.x)" y="\#(run.y)" width="\#(run.length)" height="1"/>"#)
        }

        var body = ""
        // Stable order: by ink raw value, so re-exports diff cleanly.
        for (ink, rects) in groups.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            body += "  <g id=\"ink-\(name(of: ink))\" fill=\"#\(hex(for: ink))\">\n"
            body += rects.joined(separator: "\n")
            body += "\n  </g>\n"
        }

        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="320" height="320" shape-rendering="crispEdges">
        \(body)</svg>
        """
    }

    /// The palette as hex, one entry per ink. Pinned against the live
    /// renderer's colours by a test, so the vectors cannot drift from the
    /// sprite. Exhaustive on purpose: a new ink refuses to build until it gets
    /// a hex here.
    static func hex(for ink: PixelBuffer.Ink) -> String {
        switch ink {
        case .clear: "000000"           // never emitted; runs skip clear
        case .body: "CE7B5C"
        case .eye: "000000"
        case .mouth: "FFFFFF"
        case .screenDark: "2E3A87"
        case .screenLight: "4756B8"
        case .green: "3FA34D"
        case .yellow: "E8B84B"
        case .pink: "E86A9A"
        case .steel: "8A8F98"
        case .flame: "E8712F"
        case .flameCore: "F7D046"
        case .ember: "C4451F"
        case .paper: "F0EEE6"
        }
    }

    private static func name(of ink: PixelBuffer.Ink) -> String {
        switch ink {
        case .clear: "clear"
        case .body: "body"
        case .eye: "eye"
        case .mouth: "mouth"
        case .screenDark: "screenDark"
        case .screenLight: "screenLight"
        case .green: "green"
        case .yellow: "yellow"
        case .pink: "pink"
        case .steel: "steel"
        case .flame: "flame"
        case .flameCore: "flameCore"
        case .ember: "ember"
        case .paper: "paper"
        }
    }
}
