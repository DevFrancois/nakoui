import SwiftUI

/// A stat's value with its unit, formatted for the reader's locale. Units stay
/// as written, so they match the figures in the facts.
struct HigherLowerStatValue: View {
    let stat: HigherLowerStat
    let value: Double

    private var number: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(0))
    }

    private var whole: Int {
        Int(value.rounded())
    }

    var body: some View {
        switch stat {
        case .weight:
            Text(
                Measurement(value: value, unit: UnitMass.kilograms),
                format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: number)
            )
        case .height:
            Text(
                Measurement(value: value, unit: UnitLength.centimeters),
                format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: number)
            )
        case .speed:
            Text(
                Measurement(value: value, unit: UnitSpeed.kilometersPerHour),
                format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: number)
            )
        case .sleep:
            Text(
                Measurement(value: value, unit: UnitDuration.hours),
                format: .measurement(width: .wide, usage: .asProvided, numberFormatStyle: number)
            )
        case .lifespan:
            Text("^[\(whole) year](inflect: true)")
        case .teeth:
            Text("\(whole) teeth")
        case .heartRate:
            Text("\(whole) bpm")
                .accessibilityLabel(Text("\(whole) beats per minute"))
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        HigherLowerStatValue(stat: .weight, value: 30)
        HigherLowerStatValue(stat: .height, value: 81)
        HigherLowerStatValue(stat: .speed, value: 70)
        HigherLowerStatValue(stat: .sleep, value: 14)
        HigherLowerStatValue(stat: .lifespan, value: 13)
        HigherLowerStatValue(stat: .teeth, value: 42)
        HigherLowerStatValue(stat: .heartRate, value: 350)
    }
    .font(.largeTitle)
    .bold()
}
