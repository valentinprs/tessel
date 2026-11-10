import CoreGraphics

enum GridFormat: String, CaseIterable, Identifiable {
    case square
    case portrait
    case landscape
    case story
    case classic

    var id: Self { self }

    var title: String {
        switch self {
        case .square: "Carré"
        case .portrait: "Portrait"
        case .landscape: "Paysage"
        case .story: "Story"
        case .classic: "Classique"
        }
    }

    var ratioLabel: String {
        switch self {
        case .square: "1:1"
        case .portrait: "4:5"
        case .landscape: "16:9"
        case .story: "9:16"
        case .classic: "3:2"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .square: 1
        case .portrait: 4 / 5
        case .landscape: 16 / 9
        case .story: 9 / 16
        case .classic: 3 / 2
        }
    }
}
