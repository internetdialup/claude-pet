import SwiftUI

/// The click-through panel: every live Claude session, what it is doing, and
/// which one the crab is mirroring.
public struct RosterPanel: View {
    public var state: PetState
    public var pinnedID: String?
    public var onPin: (String?) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude sessions")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
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
                ScrollView {
                    VStack(spacing: 0) {
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
                }
                .frame(maxHeight: 280)
            }

            if pinnedID != nil {
                Divider()
                Button("Unpin — follow the busiest session") { onPin(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
            .background(isFocused ? Palette.body.opacity(0.10) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin this session" : "Pin the crab to this session")
    }
}
