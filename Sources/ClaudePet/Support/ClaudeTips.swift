import Foundation

// ═════════════════════════════════════════════════════════════════════════════
//  💡  CLAUDE CODE TIPS — the things he knows about the tool you are holding.
// ═════════════════════════════════════════════════════════════════════════════
//
//  Separate from `FunFacts.swift`, and the reason is the same shape as the
//  reason that file is separate from `vocab.swift` — one more turn of the same
//  screw.
//
//  A vocabulary line cannot be WRONG; it is an opinion in the operator's voice.
//  A fun fact can be wrong, so it carries sources and a review gate. **A tip
//  can be wrong in a way a fact cannot: it can go stale.** A fact about 1971
//  will still be true in 1971. A sentence about a slash command is a claim
//  about software that ships every week, made from a binary that ships once.
//
//  ── The rules, which are the fun-fact rules plus two ─────────────────────────
//
//  1. **Verified against the build, not against the documentation.** This is
//     not pedantry. When these were written the live docs still listed `/vim`
//     and `/output-style`, and both had been removed; `/todos` appears in no
//     build at all — the surface people mean is `/tasks`. A tip drafted from
//     memory or from a docs page would have shipped three dead commands.
//  2. **It must age into STALE, never into WRONG.** Prefer a sentence that
//     stays true when a command gains abilities, and distrust one that turns
//     false when a default flips. "`/clear` empties the context" survives a
//     dozen releases. "`/clear` is the only way to empty the context" does not.
//  3. No percentages, dollar figures or benchmark scores.
//  4. No model generation names — `StatusTicker.knownModels` is the proof they
//     churn, and the fun-fact suite guards this pool against that same list.
//  5. No moving superlatives.
//  6. **Written in his own words.** Claude Code ships its own rotating tips,
//     and several of these subjects appear in that array verbatim. The house
//     rule is *evocative, never copied*: where the vendor already says a true
//     thing well, this file says the same true thing differently.
//
//  ── What is deliberately absent ──────────────────────────────────────────────
//
//  Commands that are real and still did not make it, each for a reason worth
//  keeping: `/radio` (guarded by a feature flag that defaults to false — real
//  string, no command); `/fork` (TWO conflicting registrations inside one
//  binary); `/statusline` and `/terminal-setup` (mid-rename, or no single true
//  sentence to quote); `/review` (the binary and the docs disagree about
//  whether it is its own command); `/stickers` and the other novelties (real,
//  charming, and the first things to be folded into something else).
//
//  The length budget is `FunFacts`': 69 characters, and anything at or under
//  `ThoughtBubble.plainColumns` is shown whole instead of scrolling.
//
public enum ClaudeTips {

    /// Every tip. One flat pool — there is no ratio to hold here, so there is
    /// no mix, and `LineCursor` deals it under the id `"tip"`.
    public static let all: [String] = [
        // "Ask a quick side question without interrupting the main
        // conversation." Unusually safe for a young command: it is one of only
        // four permanent hints under the input box, which is far stronger
        // placement than a registry entry alone.
        "/btw asks a side question without derailing the main one",
        // A skill is a DIRECTORY holding a file named exactly SKILL.md, and the
        // DIRECTORY's name is what you type. The loader accepts only that
        // shape — so a loose .md dropped in `.claude/skills/` is not a skill,
        // whatever a stale in-app tip says. An earlier draft ended "its name is
        // the command", which has two antecedents in one clause and names the
        // wrong one half the time; the file's name is fixed and says nothing.
        "A skill is a folder named for the command, holding a SKILL.md",
        // The half people get wrong: /clear is not destructive. "Start a new
        // session with empty context; previous session stays on disk
        // (resumable with /resume)."
        "/clear empties the context; the old session waits in /resume",
        // "Free up context by summarizing the conversation so far", and it
        // keeps you in the SAME conversation — which is the real difference
        // from /clear. An earlier draft said "instead of dropping it", which
        // promises too much: compaction DOES drop the raw turns and leaves a
        // summary standing in for them.
        "/compact summarizes the conversation and keeps you inside it",
        // "Visualize current context usage as a colored grid."
        "/context draws what is filling your context window",
        // "Restore the code AND/OR conversation to a previous point." The
        // choice is the point — it is a picker, and the common use restores one
        // of the two. A draft promising both together would frighten off
        // anyone who wants the code back and the transcript kept.
        "/rewind can roll back the code, the conversation, or both",
        // "Open a memory file in your editor." A memory file, not THE memory
        // file: user, project and local all load, and the command offers the
        // choice. The second clause is the unguessable half — this is the
        // sanctioned replacement for the REMOVED "#" prefix, so anyone still
        // reaching for that shortcut is reaching for something gone.
        "/memory opens a memory file to edit; the # shortcut is gone",
        // Every CLAUDE.md from the filesystem root down to the working
        // directory is loaded and CONCATENATED, nearest last. They stack; a
        // nearer file does not replace a further one.
        "Every CLAUDE.md on the path is loaded, nearest one last",
        // "Manage allow and deny tool permission rules." BOTH halves: an
        // earlier draft sold only the allow side, and someone who opens it
        // expecting a list of past approvals to bless finds a rules dialog.
        "/permissions holds the allow and deny rules behind the prompts",
        // default -> acceptEdits -> plan -> bypassPermissions -> auto. Only the
        // first three are always in the cycle, so only plan mode is named.
        "Shift+Tab cycles the permission modes, plan mode among them",
        // The build's own input hints: "! for shell mode", "@ for file paths",
        // "/ for commands".
        "! runs a shell command, @ finds a file, / opens the commands",
        // Gated to macOS on purpose — that is where the surprise is — and
        // scoped to IMAGES, because cmd+v still pastes text perfectly well.
        // Reworded from the draft, which was Anthropic's own tip string almost
        // verbatim; true is not enough when the house rule is evocative,
        // never copied.
        "An image needs ctrl+v on macOS; cmd+v will not carry it",
        // "Health-check your setup and fix issues: installation, unused
        // extensions, duplicated or bloated memory files, slow hooks, updates,
        // permissions."
        "/doctor checks the install, the memory files and the hooks",
        // Reads and explores; edits stay blocked until you approve.
        "In plan mode Claude explores but cannot edit until you agree",
        // "Send a subagent off with your full context; its result comes back
        // here." Exactly those two claims and no third: the draft added "and
        // waits", which is an invented mechanic — nothing establishes that the
        // main thread blocks, and a reader who believed it would sit idle.
        "/subtask hands a subagent your context; the answer returns to you",
        // "Show which loaded skills are unused and costing context."
        "/skill-doctor lists loaded skills that nothing is using",
    ]

    /// The commands this file is allowed to name, and nothing else.
    ///
    /// Not decoration — it is the guard. Every one of these was confirmed
    /// against the installed build's own command registry, by more than one
    /// sweep. `ClaudeTipTests` pulls every `/word` out of every tip and checks
    /// it against this set, so a future tip about a command nobody verified
    /// fails the suite rather than shipping.
    ///
    /// Adding a name here is the deliberate act. That is the point: it should
    /// cost a moment's thought, because the last time this was done from
    /// memory the answer included three commands that no longer exist.
    public static let vouchedCommands: Set<String> = [
        "btw", "clear", "compact", "context", "rewind", "memory",
        "permissions", "resume", "doctor", "subtask", "skill-doctor",
    ]
}
