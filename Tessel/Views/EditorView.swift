import PhotosUI
import SwiftUI
import UIKit

struct EditorView: View {
    @State private var step: FlowStep = .photos
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [SelectedPhoto] = []
    @State private var format: GridFormat = .portrait
    @State private var layout: GridLayoutOption = .balanced
    @State private var spacing: Double = 4
    @State private var margin: Double = 0
    @State private var areSpacingControlsVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?

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
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .photos {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            previousStep()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Étape précédente")
                    }
                }
            }
            .toolbarBackground(EditorPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if step == .preview {
                    editorToolbar
                } else {
                    nextButton
                }
            }
            .alert(
                "Impossible de charger les photos",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: pickerItems) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(EditorPalette.accent)
        .preferredColorScheme(.dark)
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
        .accessibilityLabel("Étape \(step.rawValue + 1) sur \(FlowStep.allCases.count)")
    }

    private var photoSelectionStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Choisis jusqu’à 9 photos dans l’ordre où tu veux les voir.")
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
                            Image(systemName: photos.isEmpty ? "photo.on.rectangle.angled" : "photo.badge.plus")
                                .font(.system(size: 36, weight: .medium))
                        }

                        Text(photos.isEmpty ? "Sélectionner des photos" : "Modifier la sélection")
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
                Text("Choisis les proportions finales de la grille.")
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
                Text("Choisis comment les photos occupent l’espace.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(GridLayoutOption.available(for: photos.count)) { option in
                        Button {
                            withAnimation(.snappy) {
                                layout = option
                            }
                        } label: {
                            VStack(spacing: 12) {
                                LayoutDiagram(
                                    layout: option,
                                    photoCount: photos.count,
                                    isSelected: layout == option
                                )
                                .frame(height: 96)

                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(EditorPalette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        layout == option ? EditorPalette.accent : .white.opacity(0.06),
                                        lineWidth: 1.5
                                    )
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var previewStep: some View {
        GeometryReader { proxy in
            let mosaicSize = fittedMosaicSize(in: proxy.size)

            GridCanvas(
                photos: photos,
                layout: layout,
                spacing: spacing,
                margin: margin,
                cornerRadius: 0,
                backgroundColor: .white
            )
            .frame(width: mosaicSize.width, height: mosaicSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func fittedMosaicSize(in containerSize: CGSize) -> CGSize {
        let availableWidth = max(0, containerSize.width - 40)
        let availableHeight = max(0, containerSize.height - 40)
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

    private var editorToolbar: some View {
        VStack(spacing: 0) {
            if areSpacingControlsVisible {
                spacingControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Rectangle()
                .fill(EditorPalette.separator)
                .frame(height: 1)

            HStack {
                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        areSpacingControlsVisible.toggle()
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 24)

                        Text("Espacements")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(
                        areSpacingControlsVisible
                            ? EditorPalette.accent
                            : .white.opacity(0.78)
                    )
                    .frame(minWidth: 96, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Espacement et marge")

                Spacer()
            }
            .frame(height: 68)
        }
        .background(EditorPalette.toolbar)
    }

    private var spacingControls: some View {
        VStack(spacing: 22) {
            editorSlider(
                title: "Entre les photos",
                value: $spacing,
                minimumIcon: "rectangle.compress.vertical",
                maximumIcon: "rectangle.expand.vertical"
            )

            editorSlider(
                title: "Marge extérieure",
                value: $margin,
                minimumIcon: "square",
                maximumIcon: "square.dashed"
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(EditorPalette.raisedSurface)
    }

    private func editorSlider(
        title: String,
        value: Binding<Double>,
        minimumIcon: String,
        maximumIcon: String
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
                Image(systemName: minimumIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: value, in: 0...32, step: 1)
                    .tint(EditorPalette.accent)

                Image(systemName: maximumIcon)
                    .font(.caption)
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
                    Image(systemName: "arrow.right")
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

    private func nextStep() {
        guard let next = FlowStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.snappy) {
            step = next
        }
    }

    private func previousStep() {
        guard let previous = FlowStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy) {
            if step == .preview {
                areSpacingControlsVisible = false
            }
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

        withAnimation(.snappy) {
            photos = loaded
            if !GridLayoutOption.available(for: loaded.count).contains(layout) {
                layout = .balanced
            }
        }
    }
}

private enum FlowStep: Int, CaseIterable, Identifiable {
    case photos
    case ratio
    case layout
    case preview

    var id: Self { self }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .ratio: "Ratio"
        case .layout: "Disposition"
        case .preview: "Aperçu"
        }
    }

    var buttonTitle: String {
        switch self {
        case .photos: "Choisir le ratio"
        case .ratio: "Choisir la disposition"
        case .layout: "Afficher la grille"
        case .preview: ""
        }
    }
}

private struct LayoutDiagram: View {
    let layout: GridLayoutOption
    let photoCount: Int
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = min(max(photoCount, 1), 5)
            let frames = layout.frames(count: count, in: proxy.size, spacing: 3)

            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            isSelected
                                ? EditorPalette.accent.opacity(index == 0 ? 0.9 : 0.45)
                                : Color.secondary.opacity(index == 0 ? 0.48 : 0.22)
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private enum EditorPalette {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let surface = Color(red: 0.105, green: 0.113, blue: 0.125)
    static let raisedSurface = Color(red: 0.125, green: 0.133, blue: 0.145)
    static let control = Color(red: 0.17, green: 0.18, blue: 0.20)
    static let toolbar = Color(red: 0.075, green: 0.08, blue: 0.09)
    static let separator = Color.white.opacity(0.1)
    static let accent = Color(red: 0.30, green: 0.69, blue: 0.96)
}
