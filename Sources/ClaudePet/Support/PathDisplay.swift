import Foundation

/// The operator's home directory never reaches a screen surface.
///
/// Bubbles, tooltips, the roster and the installer's dialogs all show strings
/// that can carry an absolute path — a Bash command, a grep pattern, a session's
/// working directory. On a stock Mac the account segment of that path is a
/// person's name, and the pet is exactly the kind of thing that ends up in a
/// screen recording. Every such string goes through here first, and the home
/// prefix becomes `~` wherever it appears in the string, not just at the front.
public enum PathDisplay {
    nonisolated public static func abbreviatingHome(
        _ text: String,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        guard home.count > 1 else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }
}
