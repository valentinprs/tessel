import CoreGraphics
import Foundation

/// A layout is a tree: each split places its children side by side
/// (horizontal) or stacked (vertical), sized by their weights. Leaves are
/// photo slots; slot `n` receives the n-th selected photo.
struct LayoutNode: Hashable, Codable {
    enum Axis: Hashable, Codable {
        case horizontal
        case vertical

        var perpendicular: Axis {
            self == .horizontal ? .vertical : .horizontal
        }
    }

    var axis: Axis
    var children: [LayoutNode]
    var weights: [CGFloat]
    var slot: Int

    static func photo(_ slot: Int) -> LayoutNode {
        LayoutNode(axis: .horizontal, children: [], weights: [], slot: slot)
    }

    static func split(
        _ axis: Axis,
        _ children: [LayoutNode],
        weights: [CGFloat]? = nil
    ) -> LayoutNode {
        if children.count == 1 { return children[0] }
        return LayoutNode(
            axis: axis,
            children: children,
            weights: weights ?? Array(repeating: 1, count: children.count),
            slot: -1
        )
    }

    /// A line of `count` photos along `axis`, numbered from `firstSlot`.
    static func line(_ count: Int, along axis: Axis, firstSlot: Int) -> LayoutNode {
        split(axis, (0..<count).map { photo(firstSlot + $0) })
    }

    var isPhoto: Bool { children.isEmpty }

    var photoCount: Int {
        isPhoto ? 1 : children.reduce(0) { $0 + $1.photoCount }
    }

    func node(at path: [Int]) -> LayoutNode {
        guard let first = path.first else { return self }
        return children[first].node(at: Array(path.dropFirst()))
    }

    mutating func setWeights(_ newWeights: [CGFloat], at path: [Int]) {
        guard let first = path.first else {
            weights = newWeights
            return
        }
        children[first].setWeights(newWeights, at: Array(path.dropFirst()))
    }
}

/// The gap between two neighbouring children of a split, which the user can
/// drag to redistribute space between them.
struct LayoutDivider: Identifiable {
    let path: [Int]
    let index: Int
    let axis: LayoutNode.Axis
    let rect: CGRect
    /// Length shared by the split's children, used to turn a drag distance
    /// into a weight change.
    let span: CGFloat

    var id: String {
        path.map(String.init).joined(separator: ".") + ":\(index)"
    }
}

struct LayoutGeometry {
    var frames: [CGRect]
    var dividers: [LayoutDivider]
}

extension LayoutNode {
    func geometry(in rect: CGRect, spacing: CGFloat) -> LayoutGeometry {
        var geometry = LayoutGeometry(
            frames: Array(repeating: .zero, count: photoCount),
            dividers: []
        )
        place(in: rect, spacing: spacing, path: [], into: &geometry)
        return geometry
    }

    func frames(in size: CGSize, spacing: CGFloat) -> [CGRect] {
        geometry(in: CGRect(origin: .zero, size: size), spacing: spacing).frames
    }

    private func place(
        in rect: CGRect,
        spacing: CGFloat,
        path: [Int],
        into geometry: inout LayoutGeometry
    ) {
        guard !isPhoto else {
            if geometry.frames.indices.contains(slot) {
                geometry.frames[slot] = rect
            }
            return
        }

        let isHorizontal = axis == .horizontal
        let length = isHorizontal ? rect.width : rect.height
        let span = max(0, length - spacing * CGFloat(children.count - 1))
        let totalWeight = weights.reduce(0, +)
        var offset = isHorizontal ? rect.minX : rect.minY

        for (index, child) in children.enumerated() {
            let size = totalWeight > 0 ? span * weights[index] / totalWeight : 0
            let childRect = isHorizontal
                ? CGRect(x: offset, y: rect.minY, width: size, height: rect.height)
                : CGRect(x: rect.minX, y: offset, width: rect.width, height: size)
            child.place(in: childRect, spacing: spacing, path: path + [index], into: &geometry)
            offset += size

            if index < children.count - 1 {
                let gap = isHorizontal
                    ? CGRect(x: offset, y: rect.minY, width: spacing, height: rect.height)
                    : CGRect(x: rect.minX, y: offset, width: rect.width, height: spacing)
                geometry.dividers.append(
                    LayoutDivider(path: path, index: index, axis: axis, rect: gap, span: span)
                )
            }
            offset += spacing
        }
    }
}

struct GridLayout: Identifiable, Hashable {
    enum Family: String, CaseIterable, Identifiable, Codable {
        case rows
        case columns
        case featured

        var id: Self { self }

        var title: String {
            switch self {
            case .rows: "Rows"
            case .columns: "Columns"
            case .featured: "Featured"
            }
        }

    }

    let id: String
    let family: Family
    let title: String
    let template: LayoutNode
    /// The template with the proportions the user dragged into place.
    var root: LayoutNode

    init(id: String, family: Family, title: String, root: LayoutNode) {
        self.init(id: id, family: family, title: title, template: root, root: root)
    }

    /// Restores a layout whose proportions were edited, e.g. from a saved frame.
    init(id: String, family: Family, title: String, template: LayoutNode, root: LayoutNode) {
        self.id = id
        self.family = family
        self.title = title
        self.template = template
        self.root = root
    }

    static func == (lhs: GridLayout, rhs: GridLayout) -> Bool {
        lhs.id == rhs.id && lhs.root == rhs.root
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension GridLayout {
    private static let maximumLines = 4
    private static let maximumPhotosPerLine = 4

    static func suggestions(for photoCount: Int) -> [GridLayout] {
        Family.allCases.flatMap { suggestions(for: photoCount, family: $0) }
    }

    static func suggestions(for photoCount: Int, family: Family) -> [GridLayout] {
        guard photoCount > 0 else { return [] }
        guard photoCount > 1 else {
            return family == .rows
                ? [GridLayout(id: "single", family: .rows, title: "Full frame", root: .photo(0))]
                : []
        }

        switch family {
        case .rows:
            return lineLayouts(for: photoCount, family: .rows, linesAxis: .vertical)
        case .columns:
            return lineLayouts(for: photoCount, family: .columns, linesAxis: .horizontal)
        case .featured:
            return featuredLayouts(for: photoCount)
        }
    }

    /// Every way to split the photos into 2 to 4 lines (rows or columns),
    /// keeping lines reasonably balanced so no layout looks broken.
    private static func lineLayouts(
        for photoCount: Int,
        family: Family,
        linesAxis: LayoutNode.Axis
    ) -> [GridLayout] {
        let idealLines = max(2, Int(Double(photoCount).squareRoot().rounded()))
        var candidates: [[Int]] = []

        for lineCount in 2...min(photoCount, maximumLines) {
            candidates += compositions(of: photoCount, into: lineCount, maximumPart: maximumPhotosPerLine)
                .filter { parts in
                    let spread = parts.max()! - parts.min()!
                    return spread <= 1 || (spread == 2 && lineCount <= 3)
                }
        }

        candidates.sort { lhs, rhs in
            let lhsKey = (abs(lhs.count - idealLines), lhs.max()! - lhs.min()!)
            let rhsKey = (abs(rhs.count - idealLines), rhs.max()! - rhs.min()!)
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return lhs.lexicographicallyPrecedes(rhs)
        }

        return candidates.map { parts in
            var nextSlot = 0
            let lines = parts.map { count in
                defer { nextSlot += count }
                return LayoutNode.line(count, along: linesAxis.perpendicular, firstSlot: nextSlot)
            }
            let prefix = family == .rows ? "R" : "C"
            return GridLayout(
                id: "\(prefix)-" + parts.map(String.init).joined(separator: "."),
                family: family,
                title: parts.map(String.init).joined(separator: " · "),
                root: .split(linesAxis, lines)
            )
        }
    }

    private static func featuredLayouts(for photoCount: Int) -> [GridLayout] {
        let others = photoCount - 1
        let groupCount = Int(ceil(Double(others) / Double(maximumPhotosPerLine)))
        let groupSizes = balancedParts(of: others, into: groupCount)

        func otherPhotos(stackedAlong axis: LayoutNode.Axis) -> LayoutNode {
            var nextSlot = 1
            let groups = groupSizes.map { count in
                defer { nextSlot += count }
                return LayoutNode.line(count, along: axis, firstSlot: nextSlot)
            }
            return .split(axis.perpendicular, groups)
        }

        let featuredWeight: CGFloat = 2
        let othersWeight = CGFloat(groupCount)
        let placements: [(String, String, LayoutNode)] = [
            ("leading", "Left", .split(
                .horizontal, [.photo(0), otherPhotos(stackedAlong: .vertical)],
                weights: [featuredWeight, othersWeight]
            )),
            ("top", "Top", .split(
                .vertical, [.photo(0), otherPhotos(stackedAlong: .horizontal)],
                weights: [featuredWeight, othersWeight]
            )),
            ("trailing", "Right", .split(
                .horizontal, [otherPhotos(stackedAlong: .vertical), .photo(0)],
                weights: [othersWeight, featuredWeight]
            )),
            ("bottom", "Bottom", .split(
                .vertical, [otherPhotos(stackedAlong: .horizontal), .photo(0)],
                weights: [othersWeight, featuredWeight]
            ))
        ]

        return placements.map { id, title, root in
            GridLayout(id: "F-\(id)", family: .featured, title: title, root: root)
        }
    }

    private static func compositions(of total: Int, into parts: Int, maximumPart: Int) -> [[Int]] {
        guard parts > 0 else { return total == 0 ? [[]] : [] }
        guard total >= parts, total <= parts * maximumPart else { return [] }

        return (1...min(maximumPart, total)).flatMap { first in
            compositions(of: total - first, into: parts - 1, maximumPart: maximumPart)
                .map { [first] + $0 }
        }
    }

    private static func balancedParts(of total: Int, into parts: Int) -> [Int] {
        (0..<parts).map { index in
            total / parts + (index < total % parts ? 1 : 0)
        }
    }
}
