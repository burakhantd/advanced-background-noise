import SwiftUI

extension Color {
    static let secondaryLayerAccent = Color(
        red: 0.52,
        green: 0.55,
        blue: 0.84
    )
}

extension TimerPreset {
    var accentColor: Color {
        switch self {
        case .fifteen:
            return Color(red: 0.18, green: 0.80, blue: 0.44)
        case .thirty:
            return Color(red: 0.55, green: 0.80, blue: 0.22)
        case .fortyFive:
            return Color(red: 0.98, green: 0.72, blue: 0.08)
        case .sixty:
            return Color(red: 0.98, green: 0.52, blue: 0.12)
        case .ninety:
            return Color(red: 0.96, green: 0.36, blue: 0.15)
        case .oneTwenty:
            return Color(red: 0.94, green: 0.22, blue: 0.22)
        }
    }
}
