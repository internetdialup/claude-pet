import SwiftUI

/// The click-through panel: every live Claude session, what it is doing, and
/// which one the crab is mirroring.
public struct RosterPanel: View {
    public var state: PetState
    public var pinnedID: String?
    public var onPin: (String?) -> Void

    /// Whether the list scrolls.
    ///
    /// `ScrollView` has no intrinsic height, and `ImageRenderer` sizes from
    /// intrinsic content — so an offline render of this panel comes out clipped
    /// or empty. Set false for a still; the live popover leaves it true.
    public var scrolls: Bool = true

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude sessions")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                // The 🐑 tally, once it is off zero.
                //
                // Hidden at zero on purpose: it should be discovered by
                // someone who left him asleep and later wondered what the
                // sheep meant, not explained by a row that is always there.
                if state.sleepTalkCount > 0 {
                    Text("🐑 \(state.sleepTalkCount)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .help("Facts he has muttered in his sleep this session")
                }
                Text("\(state.sessions.count) live")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            if state.sessions.isEmpty {
                Text("Nothing running.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                let rows = VStack(spacing: 0) {
                    ForEach(state.sessions) { session in
                        SessionRow(
                            session: session,
                            isFocused: session.id == state.focusedSessionID,
                            isPinned: session.id == pinnedID,
                            onPin: { onPin(pinnedID == session.id ? nil : session.id) }
                        )
                        Divider().opacity(0.4)
                    }
                }
                if scrolls {
                    ScrollView { rows }.frame(maxHeight: 280)
                } else {
                    rows
                }
            }

            if pinnedID != nil {
                Divider()
                UnpinRow { onPin(nil) }
            }
        }
        .frame(width: 320)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let isFocused: Bool
    let isPinned: Bool
    let onPin: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onPin) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Palette.accent(for: session.mood))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Palette.body)
                        }
                    }
                    Text(session.activeTaskLabel ?? session.activity ?? session.title ?? "idle")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(session.projectName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle(isFocused: isFocused, hovering: hovering))
        .onHover { hovering = $0 }
        .help(isPinned ? "Unpin this session" : "Pin the crab to this session")
    }
}

/// A row that admits it is a button.
///
/// These were `.buttonStyle(.plain)` with a background that only ever marked
/// the focused row: nothing lit under the pointer and nothing moved on the
/// press, so a list of clickable sessions read as a list of labels and the one
/// thing you could do with the roster was invisible.
///
/// Flat fills at four levels — rest, hover, focused, pressed — because the
/// palette forbids gradients, and eased rather than switched, because a
/// one-frame change is a glitch here for the same reason it is on the sprite.
private struct RowStyle: ButtonStyle {
    let isFocused: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let level: Double = configuration.isPressed ? 0.20
            : isFocused ? (hovering ? 0.16 : 0.10)
            : (hovering ? 0.07 : 0)
        return configuration.label
            .background(Palette.body.opacity(level))
            // The press reads faster than the hover: a click should feel
            // answered, a pointer merely acknowledged.
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}


/// The unpin action, given the same affordance as the rows above it — it used
/// to be bare text that happened to be clickable.
private struct UnpinRow: View {
    let onUnpin: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onUnpin) {
            Text("Unpin — follow the busiest session")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Palette.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle(isFocused: false, hovering: hovering))
        .onHover { hovering = $0 }
    }
}
