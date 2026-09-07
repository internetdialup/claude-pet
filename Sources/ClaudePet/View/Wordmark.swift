import SwiftUI

/// The brand's one wordmark: the string, the face, the weight.
///
/// Every renderer that sets the product's name calls this, so there is
/// exactly one place for the operator's typeface to land when it arrives.
/// "Claude Pet" in heavy rounded is what `docs/media/wordmark.png`, the
/// release banner and the social preview already ship; the reel used to set
/// "CLAUDE PET" in monospaced caps with a fixed tracking of four — a second
/// brand on one product, and the fastest "nobody owns this" signal a
/// marketing set can send. A grep test holds the literal to this file.
struct Wordmark: View {
    static let text = "Claude Pet"

    let size: CGFloat
    var color: Color = Palette.kraft

    var body: some View {
        Text(Self.text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
    }
}
