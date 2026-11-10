import SwiftUI

struct ExportSheet: View {
    let exporter: GridExporter

    @AppStorage("exportResolution") private var resolutionValue = ExportResolution.standard.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var fileURL: URL?
    @State private var isExportingToFiles = false
    @State private var isWorking = false
    @State private var toast: String?
    @State private var errorMessage: String?

    private var resolution: ExportResolution {
        ExportResolution(rawValue: resolutionValue) ?? .standard
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)

            Divider().overlay(EditorPalette.separator)

            HStack(alignment: .top) {
                roundAction("Instagram", icon: .instagram, action: shareToInstagram)
                shareAction
                roundAction("Files", icon: .folderExport) {
                    isExportingToFiles = true
                }
            }
            .padding(.vertical, 18)
            .disabled(image == nil || isWorking)

            Divider().overlay(EditorPalette.separator)

            VStack(spacing: 0) {
                Button(action: saveToPhotos) {
                    row(icon: .download, title: "Save to Photos", subtitle: "Adds the grid to your library")
                }
                .buttonStyle(.plain)
                .disabled(image == nil || isWorking)

                resolutionRow
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
        .background(EditorPalette.surface.ignoresSafeArea())
        .toast($toast)
        .task(id: resolutionValue) { prepareImage() }
        .fileExporter(
            isPresented: $isExportingToFiles,
            document: image?.jpegData(compressionQuality: 0.92).map(JPEGDocument.init(data:)),
            contentType: .jpeg,
            defaultFilename: "Tessel"
        ) { result in
            switch result {
            case .success: toast = "Saved to Files"
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Couldn’t export the grid",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                HugeiconImage(.cancel, size: 20)
                    .frame(width: 44, height: 44)
                    .background(EditorPalette.control, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Close")

            Text("Export")
                .font(.title3.weight(.semibold))

            Spacer()
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            VStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView()
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private var shareAction: some View {
        if let fileURL, let image {
            ShareLink(
                item: fileURL,
                preview: SharePreview("Tessel grid", image: Image(uiImage: image))
            ) {
                roundLabel("Share", icon: .share)
            }
            .buttonStyle(PressableButtonStyle())
            .frame(maxWidth: .infinity)
        } else {
            roundLabel("Share", icon: .share)
                .opacity(0.4)
                .frame(maxWidth: .infinity)
        }
    }

    private var resolutionRow: some View {
        Menu {
            Picker("Resolution", selection: $resolutionValue) {
                ForEach(ExportResolution.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        } label: {
            row(icon: .settings, title: "Resolution", subtitle: "Width of the exported image") {
                Text(resolution.title)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(EditorPalette.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private func roundAction(
        _ title: String,
        icon: Hugeicon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            roundLabel(title, icon: icon)
        }
        .buttonStyle(PressableButtonStyle())
        .frame(maxWidth: .infinity)
    }

    private func roundLabel(_ title: String, icon: Hugeicon) -> some View {
        VStack(spacing: 10) {
            HugeiconImage(icon, size: 24)
                .frame(width: 58, height: 58)
                .background(EditorPalette.control, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.08), lineWidth: 1) }

            Text(title)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private func row(
        icon: Hugeicon,
        title: String,
        subtitle: String
    ) -> some View {
        row(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }

    private func row<Trailing: View>(
        icon: Hugeicon,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 16) {
            HugeiconImage(icon, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func prepareImage() {
        image = exporter.render(width: resolution.rawValue)
        fileURL = image.flatMap { try? GridExporter.temporaryFile(for: $0) }
    }

    private func saveToPhotos() {
        guard let image else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await PhotoLibrary.save(image)
                toast = "Saved to Photos"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Instagram can only open posts from the photo library, so the grid is
    /// saved there first, then handed to Instagram's new-post screen.
    private func shareToInstagram() {
        guard let image else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let identifier = try await PhotoLibrary.save(image)
                try await Instagram.openNewPost(withAsset: identifier)
            } catch ExportError.instagramUnavailable {
                errorMessage = "Instagram isn’t installed on this device. The grid was saved to Photos."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A short confirmation that slides in and hides itself after two seconds.
private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 8) {
                        HugeiconImage(.checkmark, size: 20)
                            .foregroundStyle(EditorPalette.accent)
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(EditorPalette.control, in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.1), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: message)
            .sensoryFeedback(.success, trigger: message) { _, newMessage in newMessage != nil }
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                message = nil
            }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
