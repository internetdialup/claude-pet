# Repository Organization - v0.2.0

---
**Document Metadata:**
- **Created:** 2026-08-06
- **Last Updated:** 2026-08-06
- **Document Version:** v0.2.0
- **Operational Freeze Tag:** `v0.1.2-clawd-personality`
---

The folder map. This file updates in the **same commit** as any file addition or rename (`Bamboo.md` §4).

## Governance

| Path | Contents |
| :--- | :--- |
| `README.md` | What the pet is, how to run it, what it refuses to do |
| `LICENSE` | MIT, plus the note that Claw'd is Anthropic's mascot and this is unofficial |
| `AGENT.md` | Cold-start router, Session Identity, Build Target |
| `Bamboo.md` | Local operating spec, the `~/.claude` redline |
| `CLAUDE.md` | Claude-specific vendor overlay |
| `REPORTING_TEMPLATE.md` | Structural verification report format |
| `behavior/ctx-rules.md` | Reasoning and context rules (forked from canon) |
| `development/swift-development.md` | The Swift structural standard |
| `docs/ctx-orientation.md` | The Knob log |
| `docs/repo-organization.md` | This file |
| `.github/workflows/pltrf-check.yml` | The PLTRF CI gate |
| `.gitignore` | Excludes build output and anything captured from `~/.claude/` |
| `run.sh` | Builds the executable, assembles and signs `build/ClaudePet.app`, launches it |

## Source

Files are named for their **principal type** (`development/swift-development.md` §1.3).

| Path | Layer | Principal type / contents |
| :--- | :--- | :--- |
| `App/main.swift` | App | Entry point and argument modes (`--render-sheet`, `--probe`) |
| `App/AppDelegate.swift` | App | Window lifecycle, alert routing, mood preview |
| `App/MenuBarController.swift` | App | The `NSStatusItem` menu — the app's only chrome |
| `App/Probe.swift` | App | `--probe`: prints the live `PetState` and exits |
| `App/SpriteSheetRenderer.swift` | App | `--render-sheet`: the art contact sheet |
| `Window/PetWindow.swift` | View | Borderless floating window, dragging, multi-display placement |
| `Window/DockMagnet.swift` | View | Edge snapping and clamping maths |
| `Model/PetState.swift` | State | `PetState` + `PetMood` + `BubbleStyle` |
| `Model/ClaudeSession.swift` | State | One live Claude Code process |
| `Model/ClaudeHome.swift` | State | Canonical paths inside `~/.claude/` |
| `Model/ActivityEvent.swift` | State | The one event type every feed emits |
| `Feeds/SessionRegistry.swift` | Feed | Which Claude processes are actually alive |
| `Feeds/TranscriptFold.swift` | Feed | Bounded-tail transcript reader |
| `Feeds/TaskWatcher.swift` | Feed | The in-progress todo's `activeForm` |
| `Feeds/StatusTicker.swift` | Feed | Model name and usage percentages, when grounded |
| `Feeds/HookServer.swift` | Feed | Drains the hook event drop-directory |
| `Feeds/FileWatcher.swift` | Feed | Coalescing `DispatchSource` file/directory watcher |
| `Feeds/ActivityCoordinator.swift` | Feed | The single reducer: events → `PetState` |
| `View/CrabRig.swift` | View | `CrabRig` + `CrabPose`: pose → pixels |
| `View/CrabView.swift` | View | `CrabView` + `CrabAnimator`: time + mood → pose |
| `View/PixelBuffer.swift` | View | The 32×32 indexed buffer and its renderer |
| `View/ThoughtBubble.swift` | View | The speech bubble, marquee, and thinking dots |
| `View/PetRootView.swift` | View | Window layout; `PetViewModel` |
| `View/RosterPanel.swift` | View | The click-through session list |
| `Support/Palette.swift` | Support | Claw'd's flat colours |
| `Support/Preferences.swift` | Support | Persisted settings |
| `Support/SoundBank.swift` | Support | Synthesised cues |
| `Support/HookInstaller.swift` | Support | The one permitted writer to `~/.claude/` |
| `Support/vocab-shoutouts.swift` | Support | The phrase catalogue |
| `Support/Info.plist` | Support | `LSUIElement`, bundle identity |
| `Resources/claude-pet-hook.sh` | Resource | The hook shim, shipped via `Bundle.module` |
| `Tests/ClaudePetTests/` | — | Unit tests. Never touch `~/.claude/` |

Dependencies point inward: **View → Model ← Feeds** (`development/swift-development.md` §1.2).

## Branches

| Branch | Purpose |
| :--- | :--- |
| `main` | The public branch. Debug-only UI is compiled out of release builds. |
| `debug/preview-tools` | Keeps the mood-preview submenu always visible, for art work. |

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v0.2.0 | 2026-08-06 | `v0.1.2-clawd-personality` | **Hot** | Renamed files to their principal types, split `ClaudeHome`, moved the hook shim to a bundled resource, added LICENSE/.gitignore and the branch map. |
| v0.1.0 | 2026-08-06 | `v0.1.0-claude-pet-genesis` | **Hot** | Genesis. Initial folder map for the Swift package and governance layer. |
