import Foundation

/// The recognisable services the pet can name-check while a sprint talks to
/// them: the npm cube, the GitHub mark, the Linear diamond, the deploy
/// rocket. A glyph is a *display* fact, not an alert — it rides the session
/// while matching activity runs and lingers a few seconds past it.
public enum ServiceGlyph: String, Sendable, Equatable, CaseIterable {
    case npm, github, linear, deploy
}

extension ServiceGlyph {
    /// Word-boundary matchers over the lowercased raw command, in precedence
    /// order — a compound `npm run build && git push` is a push first. Each
    /// compiled once; an invalid pattern would be a programmer error, so the
    /// force-try is honest.
    private static let commandRules: [(glyph: ServiceGlyph, rule: NSRegularExpression)] = [
        (.github, try! NSRegularExpression(pattern: #"\bgit\s+push\b|\bgh\s+(pr|release|repo)\b"#)),
        (.deploy, try! NSRegularExpression(pattern: #"\bvercel\b|\bdocker\s+(build|push)\b|\b(fly|flyctl)\s+deploy\b"#)),
        (.npm, try! NSRegularExpression(pattern: #"\b(npm|yarn|pnpm|bun)\b"#)),
    ]

    /// Which service, if any, this tool call is talking to.
    ///
    /// Linear is recognised by tool NAME — an MCP call whose slug mentions
    /// linear. Best effort on purpose: claude.ai connectors use UUID slugs
    /// (`mcp__01a88bab…__save_issue`) that carry no service name, and those
    /// are a documented miss; `mcp__linearb__…` would be a documented false
    /// positive. Everything else is recognised by the raw COMMAND, which
    /// rides its own event field because the human-written description wins
    /// the `detail` extraction and rarely contains the command text.
    public static func classify(tool: String, command: String?) -> ServiceGlyph? {
        let name = tool.lowercased()
        if name.hasPrefix("mcp__"), name.contains("linear") { return .linear }
        guard let command = command?.lowercased(), !command.isEmpty else { return nil }
        let range = NSRange(command.startIndex..., in: command)
        return commandRules.first {
            $0.rule.firstMatch(in: command, range: range) != nil
        }?.glyph
    }
}
