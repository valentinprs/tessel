import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ExportResolution: Int, CaseIterable, Identifiable {
    case standard = 1080
    case high = 2160

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "1080 px"
        case .high: "2160 px"
        }
    }
}

/// Renders the edited grid at export resolution.
struct GridExporter {
    let photos: [SelectedPhoto]
    let layout: LayoutNode
    let format: GridFormat
    let spacing: CGFloat
    let margin: CGFloat
    let background: Color
    var crops: [String: PhotoCrop] = [:]
    /// Width of the on-screen preview the gap and gutter were chosen on, so the
    /// exported image keeps exactly the same proportions.
    let referenceWidth: CGFloat

    @MainActor
    func render(width: Int) -> UIImage? {
        guard referenceWidth > 0 else { return nil }
        let size = CGSize(width: referenceWidth, height: referenceWidth / format.aspectRatio)
        let renderer = ImageRenderer(
            content: GridCanvas(
                photos: photos,
                layout: layout,
                spacing: spacing,
                margin: margin,
                cornerRadius: 0,
                backgroundColor: background,
                crops: crops
            )
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = CGFloat(width) / referenceWidth
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Writes the image as a JPEG in the temporary folder, ready to be shared.
    static func temporaryFile(for image: UIImage) throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw ExportError.encodingFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tessel \(fileTimestamp()).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: .now)
    }
}

enum ExportError: LocalizedError {
    case renderingFailed
    case encodingFailed
    case photosAccessDenied
    case instagramUnavailable

    var errorDescription: String? {
        switch self {
        case .renderingFailed: "The grid couldn’t be rendered."
        case .encodingFailed: "The image couldn’t be encoded."
        case .photosAccessDenied: "Allow Tessel to add photos in Settings › Privacy › Photos."
        case .instagramUnavailable: "Instagram isn’t installed on this device."
        }
    }
}

enum PhotoLibrary {
    /// Adds the image to the photo library and returns its local identifier.
    static func save(_ image: UIImage) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photosAccessDenied
        }

        var identifier = ""
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            identifier = request.placeholderForCreatedAsset?.localIdentifier ?? ""
        }
        return identifier
    }
}

enum Instagram {
    /// Opens Instagram's new-post flow on a photo already saved to the library.
    @MainActor
    static func openNewPost(withAsset localIdentifier: String) async throws {
        let query = localIdentifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard
            let url = URL(string: "instagram://library?LocalIdentifier=\(query)"),
            await UIApplication.shared.open(url)
        else {
            throw ExportError.instagramUnavailable
        }
    }
}

struct JPEGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
