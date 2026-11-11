import UIKit

struct SelectedPhoto: Identifiable, Sendable {
    let id: String
    let image: UIImage
    /// Small copy used by the layout previews, which show many grids at once.
    let thumbnail: UIImage

    init(id: String, image: UIImage) {
        self.id = id
        self.image = image
        self.thumbnail = image.preparingThumbnail(of: Self.thumbnailSize(for: image.size)) ?? image
    }

    private static func thumbnailSize(for size: CGSize) -> CGSize {
        let longestSide: CGFloat = 240
        let scale = min(1, longestSide / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// How a photo is framed inside its cell: zoomed in by `scale` (1 fills the
/// cell exactly) and moved by `offset`, where -1 and 1 put the photo's edge
/// against the cell's edge. Being relative, it holds whatever the cell's size.
struct PhotoCrop: Hashable, Codable, Sendable {
    static let maximumScale: CGFloat = 5

    var scale: CGFloat = 1
    var offset: CGPoint = .zero

    var isDefault: Bool { scale == 1 && offset == .zero }

    /// The photo's size once it fills the cell and is zoomed in.
    static func fillSize(of image: CGSize, in cell: CGSize, scale: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0 else { return cell }
        let fill = max(cell.width / image.width, cell.height / image.height) * scale
        return CGSize(width: image.width * fill, height: image.height * fill)
    }

    /// How far the photo can move from the centre before showing an edge.
    static func maximumShift(of image: CGSize, in cell: CGSize, scale: CGFloat) -> CGSize {
        let size = fillSize(of: image, in: cell, scale: scale)
        return CGSize(
            width: max(0, (size.width - cell.width) / 2),
            height: max(0, (size.height - cell.height) / 2)
        )
    }
}
