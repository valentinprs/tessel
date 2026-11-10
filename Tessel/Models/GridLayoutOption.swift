import CoreGraphics

enum GridLayoutOption: String, CaseIterable, Identifiable {
    case balanced
    case row
    case column
    case featuredLeading
    case featuredTop

    var id: Self { self }

    var title: String {
        switch self {
        case .balanced: "Grille"
        case .row: "Ligne"
        case .column: "Colonne"
        case .featuredLeading: "À gauche"
        case .featuredTop: "En haut"
        }
    }

    static func available(for photoCount: Int) -> [GridLayoutOption] {
        photoCount > 1 ? allCases : [.balanced]
    }

    func frames(count: Int, in size: CGSize, spacing: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }

        switch self {
        case .balanced:
            return regularGridFrames(count: count, in: size, spacing: spacing)
        case .row:
            return regularFrames(rows: 1, columns: count, count: count, in: size, spacing: spacing)
        case .column:
            return regularFrames(rows: count, columns: 1, count: count, in: size, spacing: spacing)
        case .featuredLeading:
            return featuredLeadingFrames(count: count, in: size, spacing: spacing)
        case .featuredTop:
            return featuredTopFrames(count: count, in: size, spacing: spacing)
        }
    }

    private func regularGridFrames(
        count: Int,
        in size: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let columns: Int
        switch count {
        case 1: columns = 1
        case 2, 3, 4: columns = 2
        default: columns = 3
        }
        let rows = Int(ceil(Double(count) / Double(columns)))
        return regularFrames(
            rows: rows,
            columns: columns,
            count: count,
            in: size,
            spacing: spacing
        )
    }

    private func regularFrames(
        rows: Int,
        columns: Int,
        count: Int,
        in size: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let width = max(0, (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let height = max(0, (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))

        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            return CGRect(
                x: CGFloat(column) * (width + spacing),
                y: CGFloat(row) * (height + spacing),
                width: width,
                height: height
            )
        }
    }

    private func featuredLeadingFrames(
        count: Int,
        in size: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        guard count > 1 else { return [CGRect(origin: .zero, size: size)] }

        let secondaryCount = count - 1
        let featuredWidth = max(0, (size.width - spacing) * 0.62)
        let secondaryWidth = max(0, size.width - featuredWidth - spacing)
        let secondaryHeight = max(
            0,
            (size.height - spacing * CGFloat(secondaryCount - 1)) / CGFloat(secondaryCount)
        )

        var result = [CGRect(x: 0, y: 0, width: featuredWidth, height: size.height)]
        result += (0..<secondaryCount).map { index in
            CGRect(
                x: featuredWidth + spacing,
                y: CGFloat(index) * (secondaryHeight + spacing),
                width: secondaryWidth,
                height: secondaryHeight
            )
        }
        return result
    }

    private func featuredTopFrames(
        count: Int,
        in size: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        guard count > 1 else { return [CGRect(origin: .zero, size: size)] }

        let secondaryCount = count - 1
        let featuredHeight = max(0, (size.height - spacing) * 0.62)
        let secondaryHeight = max(0, size.height - featuredHeight - spacing)
        let secondaryWidth = max(
            0,
            (size.width - spacing * CGFloat(secondaryCount - 1)) / CGFloat(secondaryCount)
        )

        var result = [CGRect(x: 0, y: 0, width: size.width, height: featuredHeight)]
        result += (0..<secondaryCount).map { index in
            CGRect(
                x: CGFloat(index) * (secondaryWidth + spacing),
                y: featuredHeight + spacing,
                width: secondaryWidth,
                height: secondaryHeight
            )
        }
        return result
    }
}
