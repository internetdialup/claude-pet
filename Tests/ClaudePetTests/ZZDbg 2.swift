import Testing
import Foundation
@testable import ClaudePet
@Suite("dbg") struct ZZDbg {
    @Test("map") @MainActor func map() {
        guard ProcessInfo.processInfo.environment["DBG"] != nil else { return }
        let b = CrabRig.render(CrabAnimator.flourishPose(.kickflip, at: 0.05))
        for y in 18..<PixelBuffer.side {
            var row = ""
            for x in 0..<PixelBuffer.side {
                row += b[x, y] == .slate ? "#" : (b[x, y] == .clear ? "." : "o")
            }
            print(String(format: "%2d %@", y, row))
        }
    }
}
