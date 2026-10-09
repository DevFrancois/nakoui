import SwiftUI

/// The tile that pops onto the white card once the code is read, in the spirit
/// of the app icon Code Scanner shows: a product glyph on an icon-shaped tile.
struct ScanRevealIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237)
            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

#Preview {
    ScanRevealIcon(size: 72)
        .padding()
}
