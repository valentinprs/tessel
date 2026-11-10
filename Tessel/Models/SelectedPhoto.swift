import UIKit

struct SelectedPhoto: Identifiable {
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
