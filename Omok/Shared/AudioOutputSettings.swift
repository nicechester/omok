enum AudioOutputSettings {
    static let storageKey = "audioOutputLevel"

    enum VolumeLevel: Int, CaseIterable, Codable {
        case normal = 0
        case loud = 1
        case extraLoud = 2

        var multiplier: Float {
            switch self {
            case .normal: return 1.8
            case .loud: return 2.5
            case .extraLoud: return 3.0
            }
        }

        var label: String {
            switch self {
            case .normal: return "Normal"
            case .loud: return "Loud"
            case .extraLoud: return "Extra Loud"
            }
        }
    }

    static let defaultLevel: VolumeLevel = .normal
}
