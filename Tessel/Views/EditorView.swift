import PhotosUI
import SwiftUI
import UIKit

/// One screen: the grid stays in view at the top and the tools below it
/// change it live, so there is no step to find or to go back to.
struct EditorView: View {
    @Environment(FrameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The frame being edited, saved under this id as soon as it has photos,
    /// then again after each change.
    @State private var frameID: UUID
    @State private var lastSaved: SavedFrame?
    @State private var pendingSave: Task<Void, Never>?
    @State private var tool: EditorTool = .layout
    @State private var pickerItems: [PhotosPickerItem]
    @State private var isPickerPresented = false
    @State private var photos: [SelectedPhoto] = []
    @State private var format: GridFormat = .portrait
    @State private var layout: GridLayout = GridLayout.suggestions(for: 1)[0]
    @State private var layoutFamily: GridLayout.Family = .rows
    @State private var spacing: Double = 4
    @State private var margin: Double = 0
    @State private var background: GridBackground = .white
    @State private var crops: [String: PhotoCrop] = [:]
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

    init(session: EditorSession) {
        _frameID = State(initialValue: session.frame?.id ?? UUID())
        _pickerItems = State(initialValue: session.pickerItems)
        guard let frame = session.frame else { return }

        // Let the picker open with the frame's photos already ticked.
        _pickerItems = State(initialValue: frame.photoIDs
            .filter { !$0.hasPrefix("photo-") }
            .map { PhotosPickerItem(itemIdentifier: $0) })
        _lastSaved = State(initialValue: frame)
        _photos = State(initialValue: session.photos)
        _format = State(initialValue: frame.format)
        _layoutFamily = State(initialValue: frame.layoutFamily)
        _spacing = State(initialValue: frame.spacing)
        _margin = State(initialValue: frame.margin)
        _background = State(initialValue: frame.background)
        _crops = State(initialValue: frame.photoCrops ?? [:])

        // A photo that couldn't be read back leaves the layout with an empty
        // slot: fall back to a layout made for the photos that are left.
        if frame.layoutRoot.photoCount == session.photos.count {
            _layout = State(initialValue: frame.layout)
        } else if let suggestion = GridLayout.suggestions(for: session.photos.count).first {
            _layout = State(initialValue: suggestion)
            _layoutFamily = State(initialValue: suggestion.family)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvasArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                toolPanel
                    .frame(maxWidth: .infinity)
                    .background(EditorPalette.toolbar)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(EditorPalette.separator)
                            .frame(height: 1)
                    }
            }
            .background(EditorPalette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) {
                        HugeiconImage(.arrowLeft, size: 22)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Back to frames")
                    .accessibilityHint("Saves the frame.")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: undo) {
                        HugeiconImage(.undo, size: 22)
                            .foregroundStyle(.white)
                    }
                    .disabled(undoStack.isEmpty)
                    .accessibilityLabel("Undo")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // Plain Liquid Glass like the other bar buttons, no
                    // coloured fill.
                    Button {
                        isExportPresented = true
                    } label: {
                        Text("Export")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                    }
                    .disabled(photos.isEmpty || isLoading)
                }
            }
            .toolbarBackground(EditorPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                toolBar
            }
            .photosPicker(
                isPresented: $isPickerPresented,
                selection: $pickerItems,
                maxSelectionCount: 9,
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .automatic
            )
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
            .sheet(isPresented: $isExportPresented) {
                ExportSheet(exporter: exporter)
                    .presentationDragIndicator(.visible)
            }
            .task {
                // A new frame arrives with the photos picked on the home
                // screen, still to be loaded.
                if photos.isEmpty, !pickerItems.isEmpty {
                    await loadPhotos(from: pickerItems)
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }
            .onChange(of: layout.id) { _, _ in
                undoStack.removeAll()
            }
            .onChange(of: draft) { _, _ in
                schedulePersist()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persist() }
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
                    backgroundColor: background.color,
                    crops: crops
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

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { proxy in
            let mosaicSize = fittedMosaicSize(in: proxy.size)

            Group {
                if photos.isEmpty {
                    emptyCanvas
                } else {
                    EditableGridCanvas(
                        photos: $photos,
                        layout: $layout,
                        crops: $crops,
                        spacing: spacing,
                        margin: margin,
                        background: background.color,
                        onWillEdit: recordUndo,
                        onTap: { setFullScreen(true) }
                    )
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
                }
            }
            .frame(width: mosaicSize.width, height: mosaicSize.height)
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .animation(.snappy, value: format)
        }
    }

    private var emptyCanvas: some View {
        Button {
            isPickerPresented = true
        } label: {
            VStack(spacing: 12) {
                HugeiconImage(.imageAdd, size: 34)
                Text("Add photos")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EditorPalette.surface)
            .overlay {
                Rectangle()
                    .stroke(
                        .white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                    )
            }
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isLoading ? 0.4 : 1)
        .disabled(isLoading)
    }

    private func fittedMosaicSize(in containerSize: CGSize) -> CGSize {
        let availableWidth = max(0, containerSize.width - 40)
        let availableHeight = max(0, containerSize.height - 32)
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

    // MARK: Tools

    /// The tools, side by side at the bottom. Each one opens its panel just
    /// above, under the grid, and every change shows on the grid at once.
    private var toolBar: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.allCases) { item in
                let isSelected = item == tool
                let isEnabled = item == .photos || !photos.isEmpty

                Button {
                    withAnimation(.snappy) {
                        tool = item
                    }
                } label: {
                    VStack(spacing: 5) {
                        HugeiconImage(item.icon, size: 24)
                        Text(item.title)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(isSelected ? EditorPalette.accent : .white)
                    .opacity(isEnabled ? (isSelected ? 1 : 0.45) : 0.2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!isEnabled)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(EditorPalette.toolbar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorPalette.separator)
                .frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: tool)
    }

    @ViewBuilder
    private var toolPanel: some View {
        // Without photos, only the photo panel makes sense.
        switch photos.isEmpty ? .photos : tool {
        case .photos:
            photosPanel
        case .layout:
            layoutPanel
        case .ratio:
            ratioPanel
        case .style:
            stylePanel
        }
    }

    private var photosPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    isPickerPresented = true
                } label: {
                    VStack(spacing: 6) {
                        HugeiconImage(.imageAdd, size: 24)
                        Text(photos.isEmpty ? "Add" : "Edit")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(EditorPalette.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isLoading)
                .accessibilityLabel(photos.isEmpty ? "Add photos" : "Edit the selection")

                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    photoThumbnail(photo, index: index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollClipDisabled()
    }

    private func photoThumbnail(_ photo: SelectedPhoto, index: Int) -> some View {
        Image(uiImage: photo.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text("\(index + 1)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(0.62), in: Circle())
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    remove(photo)
                } label: {
                    HugeiconImage(.cancel, size: 12)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.7), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.25), lineWidth: 1) }
                }
                .buttonStyle(PressableButtonStyle())
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove photo \(index + 1)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo \(index + 1)")
    }

    private var layoutPanel: some View {
        VStack(spacing: 14) {
            if photos.count > 1 {
                Picker("Layout type", selection: $layoutFamily.animation(.snappy)) {
                    ForEach(GridLayout.Family.allCases) { family in
                        Text(family.title).tag(family)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GridLayout.suggestions(for: photos.count, family: layoutFamily)) { option in
                        Button {
                            guard layout.id != option.id else { return }
                            withAnimation(.snappy) {
                                layout = option
                            }
                        } label: {
                            layoutCard(option)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("\(option.family.title) \(option.title)")
                        .accessibilityAddTraits(layout.id == option.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            // Swap the whole strip when the tab changes, rather than
            // morphing cards of one family into another.
            .id(layoutFamily)
            .transition(.opacity)
        }
        .padding(.vertical, 16)
        .sensoryFeedback(.selection, trigger: layout.id)
    }

    private func layoutCard(_ option: GridLayout) -> some View {
        let isSelected = layout.id == option.id
        let height: CGFloat = 64

        return GridCanvas(
            photos: photos,
            layout: option.root,
            spacing: 2,
            margin: 0,
            cornerRadius: 1,
            backgroundColor: .white.opacity(0.9),
            usesThumbnails: true,
            crops: crops
        )
        .frame(width: height * min(format.aspectRatio, 1.6), height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .padding(8)
        .background(
            isSelected ? EditorPalette.accent.opacity(0.14) : EditorPalette.surface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? EditorPalette.accent : .white.opacity(0.06), lineWidth: 1.5)
        }
    }

    private var ratioPanel: some View {
        HStack(spacing: 8) {
            ForEach(GridFormat.allCases) { option in
                let isSelected = format == option

                Button {
                    withAnimation(.snappy) {
                        format = option
                    }
                } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(isSelected ? EditorPalette.accent : .white.opacity(0.45), lineWidth: 1.5)
                            .aspectRatio(option.aspectRatio, contentMode: .fit)
                            .frame(width: 30, height: 30)
                        Text(option.ratioLabel)
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(isSelected ? EditorPalette.accent : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(
                        isSelected ? EditorPalette.accent.opacity(0.14) : EditorPalette.surface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? EditorPalette.accent : .white.opacity(0.06), lineWidth: 1.5)
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("\(option.title), \(option.ratioLabel)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .sensoryFeedback(.selection, trigger: format)
    }

    private var stylePanel: some View {
        VStack(spacing: 20) {
            editorSlider(
                title: "Gap",
                value: $spacing,
                minimumIcon: .arrowShrink,
                maximumIcon: .arrowExpand
            )

            editorSlider(
                title: "Gutter",
                value: $margin,
                minimumIcon: .squareDashed,
                maximumIcon: .square
            )

            backgroundPicker
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

    private var exporter: GridExporter {
        GridExporter(
            photos: photos,
            layout: layout.root,
            format: format,
            spacing: spacing,
            margin: margin,
            background: background.color,
            crops: crops,
            referenceWidth: previewWidth
        )
    }

    /// Everything that is saved with the frame, to notice when it changes.
    private var draft: EditorDraft {
        EditorDraft(
            photoIDs: photos.map(\.id),
            format: format,
            layout: layout.root,
            layoutID: layout.id,
            spacing: spacing,
            margin: margin,
            background: background,
            crops: crops
        )
    }

    private func close() {
        persist()
        dismiss()
    }

    /// Saves shortly after the last change, so dragging a slider or a divider
    /// writes once instead of on every frame.
    private func schedulePersist() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    /// Saves the frame as soon as it has photos laid out in a grid.
    private func persist() {
        pendingSave?.cancel()
        pendingSave = nil
        guard
            !photos.isEmpty,
            layout.root.photoCount == photos.count
        else { return }

        // Only the framing of photos still in the frame, and not left as is.
        let photoIDs = Set(photos.map(\.id))
        let keptCrops = crops.filter { photoIDs.contains($0.key) && !$0.value.isDefault }
        let frame = SavedFrame(
            id: frameID,
            createdAt: lastSaved?.createdAt ?? .now,
            updatedAt: .now,
            photoIDs: photos.map(\.id),
            format: format,
            layoutID: layout.id,
            layoutFamily: layout.family,
            layoutTitle: layout.title,
            layoutTemplate: layout.template,
            layoutRoot: layout.root,
            spacing: spacing,
            margin: margin,
            background: background,
            photoCrops: keptCrops.isEmpty ? nil : keptCrops
        )
        if let lastSaved, frame.hasSameContent(as: lastSaved) { return }

        let thumbnailRenderer = GridExporter(
            photos: photos,
            layout: layout.root,
            format: format,
            spacing: spacing,
            margin: margin,
            background: background.color,
            crops: crops,
            referenceWidth: previewWidth > 0 ? previewWidth : 360
        )
        let thumbnail = thumbnailRenderer.render(width: 480)
        lastSaved = frame
        store.save(frame, photos: photos, thumbnail: thumbnail)
    }

    private func recordUndo() {
        undoStack.append(
            EditorSnapshot(
                photos: photos,
                layout: layout,
                spacing: spacing,
                margin: margin,
                background: background,
                crops: crops
            )
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
            crops = snapshot.crops
        }
    }

    /// Takes a photo out of the frame, and out of the picker's selection so
    /// it stays out the next time the picker opens.
    private func remove(_ photo: SelectedPhoto) {
        if let index = pickerItems.firstIndex(where: { $0.itemIdentifier == photo.id }) {
            pickerItems.remove(at: index)
        } else {
            withAnimation(.snappy) {
                photos.removeAll { $0.id == photo.id }
                fitLayoutToPhotos()
            }
        }
    }

    /// Keeps the layout when it still has one slot per photo, otherwise
    /// switches to the first layout suggested for the new count.
    private func fitLayoutToPhotos() {
        guard
            layout.root.photoCount != photos.count,
            let firstLayout = GridLayout.suggestions(for: photos.count).first
        else { return }
        layout = firstLayout
        layoutFamily = firstLayout.family
    }

    @MainActor
    private func loadPhotos(from items: [PhotosPickerItem]) async {
        // Photos already in the frame are kept as they are: only new ones
        // are read from the library.
        let loadedByID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        isLoading = items.contains { item in
            item.itemIdentifier.map { loadedByID[$0] == nil } ?? true
        }
        defer { isLoading = false }

        var loaded: [SelectedPhoto] = []
        for (index, item) in items.enumerated() {
            if let id = item.itemIdentifier, let photo = loadedByID[id] {
                loaded.append(photo)
                continue
            }
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
            fitLayoutToPhotos()
        }
    }
}

private struct EditorDraft: Equatable {
    let photoIDs: [String]
    let format: GridFormat
    let layout: LayoutNode
    let layoutID: String
    let spacing: Double
    let margin: Double
    let background: GridBackground
    let crops: [String: PhotoCrop]
}

/// Everything the undo button can roll back.
private struct EditorSnapshot {
    let photos: [SelectedPhoto]
    let layout: GridLayout
    let spacing: Double
    let margin: Double
    let background: GridBackground
    let crops: [String: PhotoCrop]
}

private enum EditorTool: Int, CaseIterable, Identifiable {
    case photos
    case layout
    case ratio
    case style

    var id: Self { self }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .layout: "Layout"
        case .ratio: "Ratio"
        case .style: "Style"
        }
    }

    var icon: Hugeicon {
        switch self {
        case .photos: .album
        case .layout: .layout
        case .ratio: .ratio
        case .style: .adjust
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
    // Drawn for Tessel in the same stroke style.
    case ratio = "icon-ratio"
    case layout = "icon-layout"
    case adjust = "icon-adjust"
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
    /// Selected states are plain white: the app has no colour of its own
    /// besides the photos.
    static let accent = Color.white
}
