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
        }
    }
}

extension GridBackground: Codable {
    /// Frames saved with a color that no longer exists fall back to white.
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = GridBackground(rawValue: rawValue) ?? .white
    }
}
