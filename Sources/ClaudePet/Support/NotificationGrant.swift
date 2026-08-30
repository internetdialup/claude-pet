import Foundation

/// Whether macOS will actually deliver our banners.
///
/// **It usually will not, and that is a consequence of a deliberate choice.**
/// `UNUserNotificationCenter` only grants authorization to an app with a stable
/// code-signing identity. This one is ad-hoc signed on purpose — a Developer ID
/// signature publishes the author's legal name and Apple Team ID inside every
/// copy — and an ad-hoc signature's hash changes on every build, so the app is
/// never registered with Notification Center at all.
///
/// Measured on a proper install: the released DMG copied into `/Applications`
/// with quarantine cleared and launched from there still produced ZERO entries
/// under `com.apple.ncprefs.plist`, where ninety-three other apps were listed.
/// Not denied — never registered. There is no error to catch and nothing for
/// the user to switch on in System Settings, because the app does not appear
/// there.
///
/// So this exists to stop the UI lying. The old code threw the result of
/// `requestAuthorization` away, which left a checked "Notifications" row and a
/// README table promising four banners, none of which could ever fire.
@MainActor
public enum NotificationGrant {
    /// Set once, from the authorization callback. False until proven otherwise
    /// — including when there is no bundle identity to ask with.
    public private(set) static var granted = false

    /// Records what macOS answered.
    public static func record(_ granted: Bool) { Self.granted = granted }

    /// What to tell someone hovering a row they cannot use.
    public static let unavailableReason =
        "Unavailable — macOS only delivers banners to signed apps, and this build "
        + "is deliberately unsigned so it carries no author identity."
}
