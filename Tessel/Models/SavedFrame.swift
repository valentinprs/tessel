import Foundation
import Observation
import UIKit

/// A grid the user made, with everything needed to reopen it in the editor.
/// Its photos are stored next to it, as JPEG copies, since the system picker
/// gives no lasting access to the photo library.
struct SavedFrame: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    /// The photos, in slot order.
    var photoIDs: [String]
    var format: GridFormat
    var layoutID: String
    var layoutFamily: GridLayout.Family
    var layoutTitle: String
    var layoutTemplate: LayoutNode
    var layoutRoot: LayoutNode
    var spacing: Double
    var margin: Double
    var background: GridBackground
    /// How each photo is framed in its cell, by photo id. Missing in frames
    /// saved before photos could be reframed.
    var photoCrops: [String: PhotoCrop]?

    var layout: GridLayout {
        GridLayout(
            id: layoutID,
            family: layoutFamily,
            title: layoutTitle,
            template: layoutTemplate,
            root: layoutRoot
        )
    }

    /// Whether both frames look the same, whenever they were saved.
    func hasSameContent(as other: SavedFrame) -> Bool {
        var other = other
        other.createdAt = createdAt
        other.updatedAt = updatedAt
        return self == other
    }
}

/// Keeps the saved frames in Application Support, one folder per frame:
/// `frame.json`, `thumbnail.jpg` and a `photos` folder.
@MainActor
@Observable
final class FrameStore {
    /// Most recently edited first.
    private(set) var frames: [SavedFrame] = []
    private(set) var thumbnails: [UUID: UIImage] = [:]

    @ObservationIgnored private let directory: URL
    /// Disk writes run one after another, off the main thread.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("Frames", isDirectory: true)
        load()
    }

    func save(_ frame: SavedFrame, photos: [SelectedPhoto], thumbnail: UIImage?) {
        frames.removeAll { $0.id == frame.id }
        frames.insert(frame, at: 0)
        thumbnails[frame.id] = thumbnail

        let folder = folder(for: frame.id)
        let images = photos.map { (id: $0.id, image: $0.image) }
        enqueueWrite {
            try Self.write(frame, images: images, thumbnail: thumbnail, to: folder)
        }
    }

    func delete(_ frame: SavedFrame) {
        frames.removeAll { $0.id == frame.id }
        thumbnails[frame.id] = nil

        let folder = folder(for: frame.id)
        enqueueWrite {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// The frame's photos, decoded and ready to draw.
    func photos(for frame: SavedFrame) async -> [SelectedPhoto] {
        await lastWrite?.value
        let photosFolder = folder(for: frame.id).appendingPathComponent("photos", isDirectory: true)
        let ids = frame.photoIDs

        return await Task.detached(priority: .userInitiated) {
            ids.compactMap { id -> SelectedPhoto? in
                let url = photosFolder.appendingPathComponent(Self.fileName(forPhoto: id))
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                return SelectedPhoto(id: id, image: image.preparingForDisplay() ?? image)
            }
        }.value
    }

    private func load() {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [SavedFrame] = []

        for folder in folders {
            guard
                let data = try? Data(contentsOf: folder.appendingPathComponent("frame.json")),
                let frame = try? decoder.decode(SavedFrame.self, from: data)
            else { continue }

            loaded.append(frame)
            let thumbnailURL = folder.appendingPathComponent("thumbnail.jpg")
            thumbnails[frame.id] = UIImage(contentsOfFile: thumbnailURL.path)
        }

        frames = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func enqueueWrite(_ operation: @escaping @Sendable () throws -> Void) {
        let previous = lastWrite
        lastWrite = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try operation()
            } catch {
                print("FrameStore: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func write(
        _ frame: SavedFrame,
        images: [(id: String, image: UIImage)],
        thumbnail: UIImage?,
        to folder: URL
    ) throws {
        let fileManager = FileManager.default
        let photosFolder = folder.appendingPathComponent("photos", isDirectory: true)
        try fileManager.createDirectory(at: photosFolder, withIntermediateDirectories: true)

        // Photos never change once picked: only new ones are written, and
        // those no longer in the frame are removed.
        let keptNames = Set(images.map { fileName(forPhoto: $0.id) })
        for (id, image) in images {
            let url = photosFolder.appendingPathComponent(fileName(forPhoto: id))
            guard !fileManager.fileExists(atPath: url.path) else { continue }
            guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
            try data.write(to: url, options: .atomic)
        }
        for name in (try? fileManager.contentsOfDirectory(atPath: photosFolder.path)) ?? []
        where !keptNames.contains(name) {
            try? fileManager.removeItem(at: photosFolder.appendingPathComponent(name))
        }

        if let data = thumbnail?.jpegData(compressionQuality: 0.85) {
            try data.write(to: folder.appendingPathComponent("thumbnail.jpg"), options: .atomic)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(frame).write(to: folder.appendingPathComponent("frame.json"), options: .atomic)
    }

    /// Picker identifiers may contain slashes: keep only safe characters.
    nonisolated private static func fileName(forPhoto id: String) -> String {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return safe + ".jpg"
    }
}
