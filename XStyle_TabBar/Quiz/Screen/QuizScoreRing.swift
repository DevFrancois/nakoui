import SwiftUI

/// The final score as a ring that fills on appear, inside a glass circle.
struct QuizScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let score: Int
    let total: Int
    let tint: Color

    @ScaledMetric(relativeTo: .largeTitle) private var size = 150.0
    @State private var shownFraction = 0.0

    private var fraction: Double {
        total > 0 ? Double(score) / Double(total) : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 12)

            Circle()
                .trim(from: 0, to: shownFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(score)/\(total)")
                .font(.largeTitle)
                .bold()
                .monospacedDigit()
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(idealWidth: size, maxWidth: size)
        .padding(24)
        .glassEffect(in: .circle)
        .onAppear(perform: fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(score) out of \(total) correct"))
    }

    private func fill() {
        if reduceMotion {
            shownFraction = fraction
        } else {
            withAnimation(.smooth(duration: 0.8).delay(0.2)) {
                shownFraction = fraction
            }
        }
    }
}

#Preview {
    QuizScoreRing(score: 6, total: 8, tint: .teal)
        .padding()
        .background(.teal.gradient)
}
