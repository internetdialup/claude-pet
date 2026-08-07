import Foundation

/// The shipped version.
///
/// Declared once here and asserted against `Info.plist` by a test. A constant
/// that quietly disagrees with the bundle it ships in is a classic release bug:
/// the About box says one thing, the installer another, and nobody notices until
/// a user reports a version that was never built.
public enum AppVersion {
    public static let current = "1.2.0"

    /// What the running bundle actually declares. `nil` outside an app bundle —
    /// `swift run` and the test target have no `Info.plist`.
    public static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The version string parsed out of the checked-in `Info.plist`, for tests.
    /// Reads the file rather than the bundle so it verifies the source of truth
    /// that `run.sh` copies, not whatever happens to be running.
    static func versionInSourcePlist(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }
}
