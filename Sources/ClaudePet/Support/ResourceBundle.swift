import Foundation

/// The module's resource bundle, resolved by hand and allowed to be absent.
///
/// SwiftPM's generated `Bundle.module` accessor probes exactly two places:
/// `Bundle.main.bundleURL + ClaudePet_ClaudePet.bundle` — which for an app is
/// BESIDE `ClaudePet.app`, not inside `Contents/Resources` where codesign
/// forces the bundle to actually live — and an absolute path into the build
/// directory of whichever machine compiled the binary. When both miss it calls
/// `fatalError`. Probe 1 has never matched a shipped build and cannot; probe 2
/// matches on exactly one machine in the world. Every downloader's copy died
/// where the developer's quietly worked.
///
/// This resolves the same bundle in the REVERSE order, and returns nil instead
/// of trapping, so "no bundle" is a value each call site can decide about:
/// - `resourceURL` first, so an installed `.app` resolves through
///   `Contents/Resources` — the directory the bundle is genuinely in;
/// - `bundleURL` second, so a bare `.build/…/ClaudePet` still finds its
///   sibling bundle while developing;
/// - once, lazily — the filesystem does not move under a running app.
enum ResourceBundle {
    static let resolved: Bundle? = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        .lazy
        .compactMap { $0?.appendingPathComponent("ClaudePet_ClaudePet.bundle") }
        .compactMap(Bundle.init(url:))
        .first
}
