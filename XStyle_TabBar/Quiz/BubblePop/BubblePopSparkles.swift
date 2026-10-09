import SwiftUI

/// A burst where a bubble popped: specks fly outward and fade around a
/// bouncing sparkle. Decorative, so VoiceOver skips it.
struct BubblePopSparkles: View {
    let tint: Color
    /// How far the specks fly.
    let radius: Double

    @State private var isBursting = false

    private static let speckCount = 8

    var body: some View {
        ZStack {
            ForEach(0..<Self.speckCount, id: \.self) { index in
                let angle = Double(index) / Double(Self.speckCount) * 2 * .pi
                let isSparkle = index.isMultiple(of: 2)

                Image(systemName: isSparkle ? "sparkle" : "circle.fill")
                    .font(isSparkle ? .callout : .caption)
                    .foregroundStyle(isSparkle ? .yellow : tint)
                    .scaleEffect(isBursting ? 0.4 : 1)
                    .offset(
                        x: isBursting ? cos(angle) * radius : 0,
                        y: isBursting ? sin(angle) * radius : 0
                    )
                    .opacity(isBursting ? 0 : 1)
            }

            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce, value: isBursting)
                .scaleEffect(isBursting ? 1.3 : 0.6)
                .opacity(isBursting ? 0 : 1)
                .animation(.easeOut(duration: 0.9), value: isBursting)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: burst)
    }

    private func burst() {
        withAnimation(.easeOut(duration: 0.6)) {
            isBursting = true
        }
    }
}

#Preview {
    BubblePopSparkles(tint: .cyan, radius: 60)
        .frame(width: 200, height: 200)
        .background(.cyan.gradient)
}
