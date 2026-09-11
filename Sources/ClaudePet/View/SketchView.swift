import AppKit
import SwiftUI

/// The sketchpad's only mutable state, so the window and the exporter look at
/// the same thing.
@MainActor
final class SketchModel: ObservableObject {
    @Published var stack: SketchScene.Stack
    @Published var status: String = ""
    /// Held still on the scrub bar instead of running, when you want one frame.
    @Published var paused = false
    @Published var scrub: Double = 0

    init(stack: SketchScene.Stack) { self.stack = stack }

    func add(_ layer: SketchScene.Layer) { stack.layers.append(layer) }
    func remove(_ id: UUID) { stack.layers.removeAll { $0.id == id } }

    func move(_ id: UUID, by delta: Int) {
        guard let i = stack.layers.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < stack.layers.count else { return }
        stack.layers.swapAt(i, j)
    }
}

/// ✏️ **The sketchpad window.**
///
/// Left: the loop, playing. Right: three bentos — what the frame is, what is in
/// it, and where it goes. Grouped by what each control AFFECTS rather than by
/// when you happen to reach for it, which is why the background sits with shape
/// and loop: all three describe the frame, none of them describe its contents.
struct SketchView: View {
    @ObservedObject var model: SketchModel
    var onExportGIF: () -> Void
    var onExportVideo: () -> Void

    /// Every family installed on the machine. Read once — `NSFontManager` walks
    /// the font directories, and doing that per keystroke is a stutter.
    private static let fontFamilies: [String] =
        NSFontManager.shared.availableFontFamilies.sorted()

    /// The preview's longest side in points. The canvas itself is up to 1920,
    /// so it is scaled down to fit rather than rendered small — same pixels,
    /// just less of the desk.
    private let previewMax: CGFloat = 460

    private var shape: SketchScene.Shape { model.stack.shape }
    private var fit: CGFloat { previewMax / max(shape.canvas.width, shape.canvas.height) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stage
            Divider()
            controls.frame(width: 330)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - The stage

    private var stage: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Group {
                if model.paused {
                    frame(at: model.scrub * model.stack.seconds)
                } else {
                    // 20fps, the house clock — and the rate a GIF can store
                    // exactly, so what plays here is what a file will hold.
                    TimelineView(.periodic(from: Date(), by: 1.0 / Double(SketchScene.fps))) { tl in
                        let elapsed = tl.date.timeIntervalSinceReferenceDate
                        frame(at: elapsed.truncatingRemainder(dividingBy: model.stack.seconds))
                    }
                }
            }
            .frame(width: shape.canvas.width * fit, height: shape.canvas.height * fit)
            .clipped()
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))

            scrubBar
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func frame(at t: Double) -> some View {
        SketchScene.scene(model.stack, t: t)
            .scaleEffect(fit, anchor: .topLeading)
            .frame(width: shape.canvas.width * fit,
                   height: shape.canvas.height * fit, alignment: .topLeading)
    }

    private var scrubBar: some View {
        HStack(spacing: 10) {
            Button(model.paused ? "Play" : "Pause") { model.paused.toggle() }
                .frame(width: 62)
            Slider(value: $model.scrub, in: 0...1) { editing in
                if editing { model.paused = true }
            }
            Text(String(format: "%.2fs / %.1fs",
                        model.scrub * model.stack.seconds, model.stack.seconds))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)
        }
        .frame(width: previewMax)
    }

    // MARK: - The three bentos

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                bento("Frame") {
                    row("shape") {
                        Picker("", selection: $model.stack.shapeIndex) {
                            ForEach(Array(SketchScene.shapes.enumerated()), id: \.offset) { i, s in
                                Text(s.name).tag(i)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    row("loop") {
                        HStack {
                            Stepper(value: $model.stack.beats, in: 2...32) {
                                Text("\(model.stack.beats) beats")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            Spacer()
                            Text(String(format: "%.1fs", model.stack.seconds))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    // 🔎 "Background", not "ground". Ground is a term of art in
                    // the renderers — the plate a cut sits on — and putting an
                    // internal word on a button made the control unreadable to
                    // anyone who had not read the renderer.
                    row("background") {
                        HStack(spacing: 5) {
                            ForEach(Array(MarketingPalette.all.enumerated()), id: \.offset) { i, c in
                                Button { model.stack.groundIndex = i } label: {
                                    Rectangle().fill(c)
                                        .frame(width: 28, height: 22)
                                        .overlay(Rectangle().stroke(
                                            i == model.stack.groundIndex
                                                ? Color.primary : Color.secondary.opacity(0.3),
                                            lineWidth: i == model.stack.groundIndex ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                bento("Content") {
                    if model.stack.layers.isEmpty {
                        Text("Empty. Add something below.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        depthLabel("front", .top)
                        // Top of the list is the FRONT, matching Figma, Sketch
                        // and Photoshop. The array runs the other way.
                        ForEach(model.stack.layers.reversed()) { layer in
                            if let bound = binding(for: layer.id) { layerRow(bound) }
                        }
                        depthLabel("back", .bottom)
                    }
                    addPalette
                }

                bento("Output") {
                    HStack(spacing: 8) {
                        Button("Export GIF", action: onExportGIF)
                        Button("Export MP4", action: onExportVideo)
                        Spacer()
                    }
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func bento<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                Rectangle().frame(height: 1).opacity(0.15)
            }
            .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - A layer row

    @ViewBuilder
    private func layerRow(_ layer: Binding<SketchScene.Layer>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(layer.wrappedValue.title)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Button { model.move(layer.wrappedValue.id, by: 1) } label: { Image(systemName: "chevron.up") }
                    .help("Bring forward")
                Button { model.move(layer.wrappedValue.id, by: -1) } label: { Image(systemName: "chevron.down") }
                    .help("Send backward")
                Button { model.remove(layer.wrappedValue.id) } label: { Image(systemName: "xmark") }
                    .help("Remove")
            }
            .buttonStyle(.borderless)

            switch layer.wrappedValue.kind {
            case .pet:    petControls(layer)
            case .bubble: bubbleControls(layer)
            default:      EmptyView()
            }

            if layer.wrappedValue.kind != .custom && layer.wrappedValue.kind != .bubble {
                slider("amount", layer.amount, 0...1)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05))
    }

    @ViewBuilder
    private func petControls(_ layer: Binding<SketchScene.Layer>) -> some View {
        Picker("", selection: layer.petKind) {
            ForEach(SketchScene.PetKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        Picker("", selection: layer.petName) {
            ForEach(petNames(for: layer.wrappedValue.petKind), id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        Picker("", selection: layer.costume) {
            ForEach(Costume.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private func bubbleControls(_ layer: Binding<SketchScene.Layer>) -> some View {
        TextField("say something…", text: layer.text, axis: .vertical)
            .lineLimit(1...3)
            .font(.system(size: 11))
            .textFieldStyle(.roundedBorder)

        HStack(spacing: 4) {
            Picker("", selection: layer.bubbleStyle) {
                Text("types").tag("plain")
                Text("scrolls").tag("marquee")
                Text("dots").tag("dots")
            }
            .pickerStyle(.segmented).labelsHidden()
        }

        // 🔎 Mood is not decoration here: it picks the bubble's colours when no
        // override is set, and `.needsAttention` additionally rewrites a plain
        // bubble into a ⚠️-wrapped marquee. Worth knowing before it surprises.
        Picker("", selection: layer.mood) {
            ForEach(PetMood.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
        }
        .labelsHidden()

        row("font") {
            Picker("", selection: layer.fontName) {
                Text("Product mono").tag(String?.none)
                ForEach(Self.fontFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
        }
        slider("size", layer.fontSize, 7...28, format: "%.0f")
        slider("speed", layer.typeSpeed, 2...80, format: "%.0f")
        slider("scale", layer.bubbleScale, 0.3...2.5)

        HStack(spacing: 8) {
            colourWell("fill", layer.fill, fallback: .green)
            colourWell("ink", layer.ink, fallback: .black)
        }

        HStack(spacing: 10) {
            Stepper(value: layer.offsetCellsX, in: -24...24) {
                Text("x \(layer.wrappedValue.offsetCellsX)")
                    .font(.system(size: 10, design: .monospaced))
            }
            Stepper(value: layer.offsetCellsY, in: -24...24) {
                Text("y \(layer.wrappedValue.offsetCellsY)")
                    .font(.system(size: 10, design: .monospaced))
            }
        }
    }

    /// A colour that can be **unset**, because nil is a real value here — it
    /// means "whatever the mood says", which is what the app itself ships.
    @ViewBuilder
    private func colourWell(_ label: String, _ value: Binding<SketchScene.RGBA?>,
                            fallback: Color) -> some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: Binding(
                get: { value.wrappedValue?.color ?? fallback },
                set: { value.wrappedValue = SketchScene.RGBA($0) }))
                .labelsHidden()
            Text(label).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            if value.wrappedValue != nil {
                Button { value.wrappedValue = nil } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("Back to the mood's own colour")
            }
        }
    }

    @ViewBuilder
    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, format: String = "%.2f") -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
        }
    }

    /// The binding for a layer by identity rather than by index, because the
    /// list is displayed reversed and an index from the reversed view would
    /// point at the wrong element the moment anything moved.
    private func binding(for id: UUID) -> Binding<SketchScene.Layer>? {
        guard let index = model.stack.layers.firstIndex(where: { $0.id == id }) else { return nil }
        return $model.stack.layers[index]
    }

    /// The two ends of the stack, said out loud. Without these the order is
    /// still a guess — and a guess you re-make every time you open it.
    private func depthLabel(_ text: String, _ edge: VerticalEdge) -> some View {
        HStack(spacing: 6) {
            Image(systemName: edge == .top ? "arrow.up.to.line" : "arrow.down.to.line")
            Text(text).textCase(.uppercase)
            Rectangle().frame(height: 1).opacity(0.2)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private func petNames(for kind: SketchScene.PetKind) -> [String] {
        switch kind {
        case .mood:     PetMood.allCases.map(\.rawValue)
        case .flourish: CrabAnimator.Flourish.allCases.map(\.rawValue)
        case .effect:   CrabAnimator.PreviewEffect.allCases.map(\.rawValue)
        }
    }

    // MARK: - Adding

    private var addPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add VFX Preset")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            chipRow(SketchScene.CanvasPreset.allCases.map { ($0.title, $0.rawValue) }) { raw in
                model.add(.init(kind: .canvas, preset: raw))
            }
            chipRow(SketchScene.SpritePreset.allCases.map { ($0.title, $0.rawValue) }) { raw in
                model.add(.init(kind: .sprite, preset: raw))
            }
            HStack(spacing: 4) {
                Button("+ Claw'd") {
                    model.add(.init(kind: .pet, petKind: .flourish,
                                    petName: CrabAnimator.Flourish.halfCab.rawValue))
                }
                Button("+ Bubble") { model.add(.init(kind: .bubble)) }
                Button("+ Sketch.swift") { model.add(.init(kind: .custom)) }
            }
            .font(.system(size: 11))
        }
    }

    private func chipRow(_ items: [(String, String)],
                         _ tap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                HStack(spacing: 4) {
                    ForEach(i..<min(i + 2, items.count), id: \.self) { j in
                        Button(items[j].0) { tap(items[j].1) }
                            .font(.system(size: 11)).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
