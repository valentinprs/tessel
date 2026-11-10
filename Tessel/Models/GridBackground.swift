import SwiftUI

/// The preset colors shown behind the photos, in the gap and gutter.
enum GridBackground: String, CaseIterable, Identifiable {
    case white
    case ivory
    case sand
    case silver
    case stone
    case graphite
    case charcoal
    case black
    case blush
    case coral
    case terracotta
    case mustard
    case sage
    case forest
    case sky
    case navy

    var id: Self { self }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var color: Color {
        switch self {
        case .white: Color(red: 1, green: 1, blue: 1)
        case .ivory: Color(red: 0.98, green: 0.96, blue: 0.91)
        case .sand: Color(red: 0.89, green: 0.83, blue: 0.73)
        case .silver: Color(red: 0.82, green: 0.82, blue: 0.83)
        case .stone: Color(red: 0.6, green: 0.6, blue: 0.6)
        case .graphite: Color(red: 0.36, green: 0.37, blue: 0.39)
        case .charcoal: Color(red: 0.17, green: 0.17, blue: 0.18)
        case .black: Color(red: 0, green: 0, blue: 0)
        case .blush: Color(red: 0.96, green: 0.82, blue: 0.82)
        case .coral: Color(red: 0.95, green: 0.5, blue: 0.43)
        case .terracotta: Color(red: 0.75, green: 0.4, blue: 0.29)
        case .mustard: Color(red: 0.89, green: 0.69, blue: 0.24)
        case .sage: Color(red: 0.66, green: 0.73, blue: 0.62)
        case .forest: Color(red: 0.2, green: 0.36, blue: 0.27)
        case .sky: Color(red: 0.62, green: 0.79, blue: 0.92)
        case .navy: Color(red: 0.13, green: 0.2, blue: 0.36)
        }
    }
}
