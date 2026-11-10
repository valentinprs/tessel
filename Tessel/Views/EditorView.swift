import PhotosUI
import SwiftUI
import UIKit

struct EditorView: View {
    @State private var step: FlowStep = .photos
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [SelectedPhoto] = []
    @State private var format: GridFormat = .portrait
    @State private var layout: GridLayout = GridLayout.suggestions(for: 1)[0]
    @State private var layoutFamily: GridLayout.Family = .rows
    @State private var spacing: Double = 4
    @State private var margin: Double = 0
    @State private var background: GridBackground = .white
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var undoStack: [EditorSnapshot] = []
    @State private var previewWidth: CGFloat = 0
    /// The full-screen grid is shown while `isFullScreenShown`, and grows out
    /// of the preview's frame (`previewFrame`) while `isFullScreenExpanded`.
    @State private var isFullScreenShown = false
    @State private var isFullScreenExpanded = false
    @State private var previewFrame: CGRect = .zero
    @State private var isExportPresented = false
    @State private var isSaving = false
    @State private var toast: String?
    @State private var saveErrorMessage: String?
    @AppStorage("exportResolution") private var exportResolution = ExportResolution.standard.rawValue

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressIndicator
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                currentStep
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(EditorPalette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .photos {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            previousStep()
                        } label: {
                            HugeiconImage(.arrowLeft, size: 22)
                        }
                        .accessibilityLabel("Previous step")
                    }
                }

                if step == .preview {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: undo) {
                            HugeiconImage(.undo, size: 22)
                        }
                        .disabled(undoStack.isEmpty)
                        .accessibilityLabel("Undo")

                        Button(action: saveToPhotos) {
                            HugeiconImage(.download, size: 22)
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Save to Photos")

                        Button {
                            isExportPresented = true
                        } label: {
                            HugeiconImage(.upload, size: 22)
                        }
                        .accessibilityLabel("Export")
                    }
                }
            }
            .toolbarBackground(EditorPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if step == .preview {
                    spacingControls
                } else {
                    nextButton
                }
            }
            .alert(
                "Couldn’t load the photos",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Couldn’t save the grid",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .sheet(isPresented: $isExportPresented) {
                ExportSheet(exporter: exporter)
                    .presentationDragIndicator(.visible)
            }
            .toast($toast)
            .onChange(of: pickerItems) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }
            .onChange(of: layout.id) { _, _ in
                undoStack.removeAll()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isFullScreenShown {
                fullScreenGrid
            }
        }
        .statusBarHidden(isFullScreenExpanded)
        .tint(EditorPalette.accent)
        .preferredColorScheme(.dark)
    }

    /// The finished grid, as large as the screen allows. It is the preview
    /// grid itself that grows from its place on screen, drawn at the preview's
    /// size then scaled, so the gap and gutter keep their look.
    private var fullScreenGrid: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let start = previewFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let previewSize = previewFrame.size
            let fullScale = previewSize.width > 0
                ? min(proxy.size.width / previewSize.width, proxy.size.height / previewSize.height)
                : 1

            ZStack {
                Color.black
                    .opacity(isFullScreenExpanded ? 1 : 0)

                GridCanvas(
                    photos: photos,
                    layout: layout.root,
                    spacing: spacing,
                    margin: margin,
                    cornerRadius: 0,
                    backgroundColor: background.color
                )
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: isFullScreenExpanded ? 0 : 2, style: .continuous))
                .scaleEffect(isFullScreenExpanded ? fullScale : 1)
                .position(
                    x: isFullScreenExpanded ? proxy.size.width / 2 : start.midX,
                    y: isFullScreenExpanded ? proxy.size.height / 2 : start.midY
                )
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { setFullScreen(false) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Grid, full screen")
        .accessibilityHint("Tap to go back to editing.")
    }

    private func setFullScreen(_ isOn: Bool) {
        let animation = Animation.spring(duration: 0.42, bounce: 0.12)
        if isOn {
            // Lay the copy over the preview first, then grow it in the next
            // transaction so the animation starts from the preview's frame.
            isFullScreenShown = true
            DispatchQueue.main.async {
                withAnimation(animation) {
                    isFullScreenExpanded = true
                }
            }
        } else {
            withAnimation(animation) {
                isFullScreenExpanded = false
            } completion: {
                isFullScreenShown = false
            }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .photos:
            photoSelectionStep
        case .ratio:
            ratioSelectionStep
        case .layout:
            layoutSelectionStep
        case .preview:
            previewStep
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(FlowStep.allCases) { item in
                Capsule()
                    .fill(
                        item.rawValue <= step.rawValue
                            ? EditorPalette.accent
                            : EditorPalette.separator
                    )
                    .frame(height: 3)
            }
        }
        .animation(.snappy, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(FlowStep.allCases.count)")
    }

    private var photoSelectionStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Pick up to 9 photos, in the order you want them to appear.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 9,
                    selectionBehavior: .ordered,
                    matching: .images,
                    preferredItemEncoding: .automatic
                ) {
                    VStack(spacing: 14) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            HugeiconImage(photos.isEmpty ? .album : .imageAdd, size: 40)
                        }

                        Text(photos.isEmpty ? "Select photos" : "Edit selection")
                            .font(.headline)

                        if !photos.isEmpty {
                            Text("\(photos.count) photo\(photos.count > 1 ? "s" : "")")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: photos.isEmpty ? 210 : 132)
                    .foregroundStyle(.white)
                    .background(EditorPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                EditorPalette.accent.opacity(0.62),
                                style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                            )
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isLoading)

                if !photos.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 8
                    ) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            selectedPhotoThumbnail(photo, index: index)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func selectedPhotoThumbnail(
        _ photo: SelectedPhoto,
        index: Int
    ) -> some View {
        GeometryReader { proxy in
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.62), in: Circle())
                .padding(6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityLabel("Photo \(index + 1)")
    }

    private var ratioSelectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose the final proportions of the grid.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(GridFormat.allCases) { option in
                        Button {
                            withAnimation(.snappy) {
                                format = option
                            }
                        } label: {
                            ratioCard(option)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func ratioCard(_ option: GridFormat) -> some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    format == option
                        ? EditorPalette.accent.opacity(0.22)
                        : EditorPalette.control
                )
                .aspectRatio(option.aspectRatio, contentMode: .fit)
                .frame(height: 62)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            format == option ? EditorPalette.accent : .white.opacity(0.18),
                            lineWidth: format == option ? 2 : 1
                        )
                }

            VStack(spacing: 2) {
                Text(option.ratioLabel)
                    .font(.headline.monospacedDigit())
                Text(option.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .padding(.horizontal, 12)
        .foregroundStyle(.white)
        .background(EditorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(format == option ? EditorPalette.accent : .white.opacity(0.06), lineWidth: 1.5)
        }
    }

    private var layoutSelectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if photos.count > 1 {
                    Picker("Layout type", selection: $layoutFamily.animation(.snappy)) {
                        ForEach(GridLayout.Family.allCases) { family in
                            Text(family.title).tag(family)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(GridLayout.suggestions(for: photos.count, family: layoutFamily)) { option in
                        Button {
                            withAnimation(.snappy) {
                                if layout.id != option.id {
                                    layout = option
                                }
                            }
                        } label: {
                            layoutCard(option)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("\(option.family.title) \(option.title)")
                        .accessibilityAddTraits(layout.id == option.id ? .isSelected : [])
                    }
                }
                // Swap the whole grid when the tab changes, rather than
                // morphing cards of one family into another.
                .id(layoutFamily)
                .transition(.opacity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sensoryFeedback(.selection, trigger: layout.id)
    }

    private func layoutCard(_ option: GridLayout) -> some View {
        let isSelected = layout.id == option.id

        return VStack(spacing: 8) {
            GridCanvas(
                photos: photos,
                layout: option.root,
                spacing: 2,
                margin: 0,
                cornerRadius: 1.5,
                backgroundColor: .white.opacity(0.9),
                usesThumbnails: true
            )
            .aspectRatio(format.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)

            Text(option.title)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? EditorPalette.accent : .white.opacity(0.78))
        }
        .frame(height: 132)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(isSelected ? EditorPalette.accent.opacity(0.12) : EditorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? EditorPalette.accent : .white.opacity(0.06), lineWidth: 1.5)
        }
    }

    private var previewStep: some View {
        GeometryReader { proxy in
            let mosaicSize = fittedMosaicSize(in: proxy.size)

            EditableGridCanvas(
                photos: $photos,
                layout: $layout,
                spacing: spacing,
                margin: margin,
                background: background.color,
                onWillEdit: recordUndo,
                onTap: { setFullScreen(true) }
            )
            .frame(width: mosaicSize.width, height: mosaicSize.height)
            .onAppear { previewWidth = mosaicSize.width }
            .onChange(of: mosaicSize.width) { _, width in previewWidth = width }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                previewFrame = frame
            }
            // The full-screen copy stands in for the preview while it is shown.
            .opacity(isFullScreenShown ? 0 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2 - 14)

            Text("Drag the dividers to resize · Hold a photo, then tap another to swap · Tap to view full screen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 14)
        }
    }

    private func fittedMosaicSize(in containerSize: CGSize) -> CGSize {
        let availableWidth = max(0, containerSize.width - 40)
        let availableHeight = max(0, containerSize.height - 76)
        guard availableWidth > 0, availableHeight > 0 else { return .zero }

        let availableRatio = availableWidth / availableHeight
        if availableRatio > format.aspectRatio {
            return CGSize(
                width: availableHeight * format.aspectRatio,
                height: availableHeight
            )
        }

        return CGSize(
            width: availableWidth,
            height: availableWidth / format.aspectRatio
        )
    }

    private var spacingControls: some View {
        VStack(spacing: 22) {
            editorSlider(
                title: "Gap",
                value: $spacing,
                minimumIcon: .arrowShrink,
                maximumIcon: .arrowExpand
            )

            editorSlider(
                title: "Gutter",
                value: $margin,
                minimumIcon: .square,
                maximumIcon: .squareDashed
            )

            backgroundPicker
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(EditorPalette.toolbar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorPalette.separator)
                .frame(height: 1)
        }
    }

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Background")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(background.title)
                    .font(.subheadline)
                    .foregroundStyle(EditorPalette.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GridBackground.allCases) { option in
                        Button {
                            guard option != background else { return }
                            recordUndo()
                            withAnimation(.snappy) {
                                background = option
                            }
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 30, height: 30)
                                .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
                                .padding(3)
                                .overlay {
                                    Circle()
                                        .stroke(EditorPalette.accent, lineWidth: 2)
                                        .opacity(option == background ? 1 : 0)
                                }
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(option == background ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .sensoryFeedback(.selection, trigger: background)
    }

    private func editorSlider(
        title: String,
        value: Binding<Double>,
        minimumIcon: Hugeicon,
        maximumIcon: Hugeicon
    ) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text("\(Int(value.wrappedValue))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(EditorPalette.accent)
                    .frame(minWidth: 28, alignment: .trailing)
            }

            HStack(spacing: 12) {
                HugeiconImage(minimumIcon, size: 18)
                    .foregroundStyle(.secondary)

                Slider(
                    value: value,
                    in: 0...32,
                    step: 1,
                    onEditingChanged: { isEditing in
                        if isEditing { recordUndo() }
                    }
                )
                .tint(EditorPalette.accent)
                .sensoryFeedback(trigger: value.wrappedValue) { _, newValue in
                    newValue == 0 || newValue == 32
                        ? .impact(weight: .medium)
                        : .selection
                }

                HugeiconImage(maximumIcon, size: 18)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var nextButton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(EditorPalette.separator)
                .frame(height: 1)

            Button {
                nextStep()
            } label: {
                HStack {
                    Text(step.buttonTitle)
                    Spacer()
                    HugeiconImage(.arrowRight, size: 22)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(EditorPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(step == .photos && photos.isEmpty)
            .opacity(step == .photos && photos.isEmpty ? 0.42 : 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(EditorPalette.toolbar)
    }

    private var exporter: GridExporter {
        GridExporter(
            photos: photos,
            layout: layout.root,
            format: format,
            spacing: spacing,
            margin: margin,
            background: background.color,
            referenceWidth: previewWidth
        )
    }

    private func recordUndo() {
        undoStack.append(
            EditorSnapshot(photos: photos, layout: layout, spacing: spacing, margin: margin, background: background)
        )
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        withAnimation(.snappy) {
            photos = snapshot.photos
            layout = snapshot.layout
            spacing = snapshot.spacing
            margin = snapshot.margin
            background = snapshot.background
        }
    }

    private func saveToPhotos() {
        let width = ExportResolution(rawValue: exportResolution)?.rawValue ?? ExportResolution.standard.rawValue
        guard let image = exporter.render(width: width) else {
            saveErrorMessage = ExportError.renderingFailed.localizedDescription
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await PhotoLibrary.save(image)
                toast = "Saved to Photos"
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }
    }

    private func nextStep() {
        guard let next = FlowStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.snappy) {
            step = next
        }
    }

    private func previousStep() {
        guard let previous = FlowStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy) {
            step = previous
        }
    }

    @MainActor
    private func loadPhotos(from items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }

        var loaded: [SelectedPhoto] = []
        for (index, item) in items.enumerated() {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    continue
                }

                loaded.append(
                    SelectedPhoto(
                        id: item.itemIdentifier ?? "photo-\(index)-\(UUID().uuidString)",
                        image: image
                    )
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        undoStack.removeAll()
        withAnimation(.snappy) {
            photos = loaded
            if layout.root.photoCount != loaded.count,
               let firstLayout = GridLayout.suggestions(for: loaded.count).first {
                layout = firstLayout
                layoutFamily = firstLayout.family
            }
        }
    }
}

/// Everything the undo button can roll back on the preview screen.
private struct EditorSnapshot {
    let photos: [SelectedPhoto]
    let layout: GridLayout
    let spacing: Double
    let margin: Double
    let background: GridBackground
}

private enum FlowStep: Int, CaseIterable, Identifiable {
    case photos
    case ratio
    case layout
    case preview

    var id: Self { self }

    var buttonTitle: String {
        switch self {
        case .photos: "Choose ratio"
        case .ratio: "Choose layout"
        case .layout: "Show grid"
        case .preview: ""
        }
    }
}

/// Icons from the free Hugeicons set (stroke rounded), stored as template
/// vector images in the asset catalog.
enum Hugeicon: String {
    case album = "hugeicons-album-02"
    case imageAdd = "hugeicons-image-add-02"
    case arrowLeft = "hugeicons-arrow-left-01"
    case arrowRight = "hugeicons-arrow-right-02"
    case undo = "hugeicons-undo-02"
    case arrowShrink = "hugeicons-arrow-shrink-02"
    case arrowExpand = "hugeicons-arrow-expand-02"
    case square = "hugeicons-square"
    case squareDashed = "hugeicons-square-dashed"
    case upload = "hugeicons-upload-01"
    case cancel = "hugeicons-cancel-01"
    case instagram = "hugeicons-instagram"
    case share = "hugeicons-share-08"
    case folderExport = "hugeicons-folder-export"
    case download = "hugeicons-download-01"
    case settings = "hugeicons-settings-02"
    case checkmark = "hugeicons-checkmark-circle-02"
}

struct HugeiconImage: View {
    let icon: Hugeicon
    let size: CGFloat

    init(_ icon: Hugeicon, size: CGFloat) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

enum EditorPalette {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let surface = Color(red: 0.105, green: 0.113, blue: 0.125)
    static let control = Color(red: 0.17, green: 0.18, blue: 0.20)
    static let toolbar = Color(red: 0.075, green: 0.08, blue: 0.09)
    static let separator = Color.white.opacity(0.1)
    static let accent = Color(red: 0.30, green: 0.69, blue: 0.96)
}
