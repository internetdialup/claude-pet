import Testing
import Foundation
@testable import ClaudePet

/// The app's two names, and why they must never agree.
///
/// The bundle identifier was renamed away from `com.internetdialup.claude-pet`
/// because that identity is status-item-poisoned on the operator's macOS 26:
/// the window server refuses to adopt any status item created under it, so the
/// menu bar crab — the app's only menu, and its only quit — never appears.
/// Bisected with minimal probe apps: the poisoned id parked its item off-screen
/// forever while a neighbouring id adopted in seconds, across reboots and
/// Control Center restarts, with no clearable record anywhere in user-space.
/// The settings suite deliberately KEPT the old name so existing installs keep
/// their costume, size, position and every other preference.
@Suite("Identity")
@MainActor
struct IdentityTests {

    /// The committed Info.plist is the identity that ships — `Bundle.main` in a
    /// test run is the test runner, so the file itself is what gets read.
    private static func shippedBundleID() throws -> String {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/ClaudePetTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/ClaudePet/Support/Info.plist")
        let data = try Data(contentsOf: plist)
        let dict = try #require(try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any])
        return try #require(dict["CFBundleIdentifier"] as? String)
    }

    /// The rename must hold: shipping the old id would make the menu bar item
    /// invisible again on any machine carrying the poison, and it is not a
    /// state anyone can see, delete, or warn about from the outside.
    @Test("The poisoned bundle id never ships again")
    func thePoisonStaysBuried() throws {
        #expect(try Self.shippedBundleID() != "com.internetdialup.claude-pet")
    }

    /// The suite must keep the OLD name — it is where every existing install's
    /// settings live — and must differ from the bundle id, which is also what
    /// makes `UserDefaults(suiteName:)` legal: Foundation refuses the pairing
    /// when the suite equals the bundle identifier.
    @Test("The settings suite keeps the old home, apart from the bundle id")
    func theSuiteStaysHome() throws {
        #expect(Preferences.suiteName == "com.internetdialup.claude-pet",
                "moving the suite orphans every existing install's settings")
        #expect(try Self.shippedBundleID() != Preferences.suiteName,
                "suite == bundle id is the pairing Foundation refuses")
    }
}
