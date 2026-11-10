import SwiftUI

struct GridCanvas: View {
    let photos: [SelectedPhoto]
    let layout: GridLayoutOption
    let spacing: CGFloat
    let margin: CGFloat
    let cornerRadius: CGFloat
    let backgroundColor: Color

    var body: some View {
        GeometryReader { proxy in
            let contentInset = min(
                max(margin, 0),
                max(0, min(proxy.size.width, proxy.size.height) / 2)
            )
            let contentSize = CGSize(
                width: max(0, proxy.size.width - contentInset * 2),
                height: max(0, proxy.size.height - contentInset * 2)
            )
            let frames = layout.frames(
                count: photos.count,
                in: contentSize,
                spacing: spacing
            )

            ZStack(alignment: .topLeading) {
                backgroundColor

                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    if frames.indices.contains(index) {
                        photoCell(photo, size: frames[index].size)
                            .offset(
                                x: frames[index].minX + contentInset,
                                y: frames[index].minY + contentInset
                            )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aperçu de la grille")
    }

    private func photoCell(_ photo: SelectedPhoto, size: CGSize) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            }
            .accessibilityLabel("Photo")
    }
}
