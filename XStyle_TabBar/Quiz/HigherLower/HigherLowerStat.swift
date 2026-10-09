import Foundation

/// What a round compares, with the words for each way the call can go.
enum HigherLowerStat {
    case weight
    case lifespan
    case speed
    case height
    case sleep
    case teeth
    case heartRate

    var title: LocalizedStringResource {
        switch self {
        case .weight: "Typical adult weight"
        case .lifespan: "Typical lifespan"
        case .speed: "Top running speed"
        case .height: "Height at the shoulder"
        case .sleep: "Sleep per day"
        case .teeth: "Adult teeth"
        case .heartRate: "Resting heart rate"
        }
    }

    var symbol: String {
        switch self {
        case .weight: "scalemass.fill"
        case .lifespan: "hourglass"
        case .speed: "speedometer"
        case .height: "ruler.fill"
        case .sleep: "moon.zzz.fill"
        case .teeth: "mouth.fill"
        case .heartRate: "waveform.path.ecg"
        }
    }

    /// Asked on the challenger's card until the call is made.
    var question: LocalizedStringResource {
        switch self {
        case .weight: "Heavier or lighter?"
        case .lifespan: "Does it live longer or shorter?"
        case .speed: "Faster or slower?"
        case .height: "Taller or shorter?"
        case .sleep: "More sleep or less?"
        case .teeth: "More teeth or fewer?"
        case .heartRate: "Faster or slower heartbeat?"
        }
    }

    /// The answer button for a call, and the verdict once it's revealed.
    func title(for guess: HigherLowerGuess) -> LocalizedStringResource {
        switch (self, guess) {
        case (.weight, .higher): "Heavier"
        case (.weight, .lower): "Lighter"
        case (.lifespan, .higher): "Longer"
        case (.lifespan, .lower): "Shorter"
        case (.speed, .higher), (.heartRate, .higher): "Faster"
        case (.speed, .lower), (.heartRate, .lower): "Slower"
        case (.height, .higher): "Taller"
        case (.height, .lower): "Shorter"
        case (.sleep, .higher): "More sleep"
        case (.sleep, .lower): "Less sleep"
        case (.teeth, .higher): "More teeth"
        case (.teeth, .lower): "Fewer teeth"
        }
    }

    /// A value with its unit written out in full, for VoiceOver announcements.
    /// Matches what `HigherLowerStatValue` shows on screen.
    func spokenValue(_ value: Double) -> String {
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let whole = Int(value.rounded())
        return switch self {
        case .weight:
            Measurement(value: value, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: number))
        case .height:
            Measurement(value: value, unit: UnitLength.centimeters)
                .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: number))
        case .speed:
            Measurement(value: value, unit: UnitSpeed.kilometersPerHour)
                .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: number))
        case .sleep:
            Measurement(value: value, unit: UnitDuration.hours)
                .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: number))
        case .lifespan:
            String(AttributedString(localized: "^[\(whole) year](inflect: true)").characters)
        case .teeth:
            String(localized: "\(whole) teeth")
        case .heartRate:
            String(localized: "\(whole) beats per minute")
        }
    }
}
