import PhotosUI
import SwiftUI

/// What the editor opens with: the photos just picked for a new frame, or
/// a saved frame and its photos.
struct EditorSession: Identifiable {
    let id = UUID()
    var frame: SavedFrame?
    var photos: [SelectedPhoto] = []
    var pickerItems: [PhotosPickerItem] = []
}

struct HomeView: View {
    @Environment(FrameStore.self) private var store
    @State private var session: EditorSession?
    @State private var openingFrameID: UUID?
    @State private var frameToDelete: SavedFrame?
    @State private var isPickerPresented = false
    @State private var newPhotos: [PhotosPickerItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    newFrameButton

                    if store.frames.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Your frames")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(store.frames.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(store.frames) { frame in
                                    frameCell(frame)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.snappy, value: store.frames.map(\.id))
            }
            .background(EditorPalette.background.ignoresSafeArea())
            .navigationTitle("Tessel")
            .toolbarBackground(EditorPalette.background, for: .navigationBar)
            .alert(
                "Delete this frame?",
                isPresented: Binding(
                    get: { frameToDelete != nil },
                    set: { if !$0 { frameToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let frameToDelete { store.delete(frameToDelete) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The photos in your library aren’t affected.")
            }
        }
        // A new frame starts with the photos: the editor opens on the grid
        // once they're picked, and nothing happens if the picker is cancelled.
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $newPhotos,
            maxSelectionCount: 9,
            selectionBehavior: .ordered,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: newPhotos) { _, items in
            guard !items.isEmpty else { return }
            session = EditorSession(pickerItems: items)
            newPhotos = []
        }
        .fullScreenCover(item: $session) { session in
            EditorView(session: session)
                .environment(store)
        }
        .tint(EditorPalette.accent)
        .preferredColorScheme(.dark)
    }

    private var newFrameButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 10) {
                HugeiconImage(.imageAdd, size: 22)
                Text("New frame")
                    .font(.headline)
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .glassPill()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HugeiconImage(.album, size: 36)
                .foregroundStyle(.secondary)
            Text("Your frames will appear here, ready to be edited again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func frameCell(_ frame: SavedFrame) -> some View {
        Button {
            open(frame)
        } label: {
            ZStack {
                EditorPalette.surface

                if let thumbnail = store.thumbnails[frame.id] {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                }

                if openingFrameID == frame.id {
                    Color.black.opacity(0.45)
                    ProgressView()
                }
            }
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(openingFrameID != nil)
        .contextMenu {
            Button(role: .destructive) {
                frameToDelete = frame
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(
            "\(frame.format.title) frame, \(frame.photoIDs.count) photos, edited \(frame.updatedAt.formatted(.relative(presentation: .named)))"
        )
        .accessibilityHint("Opens the frame for editing.")
    }

    private func open(_ frame: SavedFrame) {
        openingFrameID = frame.id
        Task {
            let photos = await store.photos(for: frame)
            openingFrameID = nil
            session = EditorSession(frame: frame, photos: photos)
        }
    }
}

extension View {
    /// Apple's default Liquid Glass on iOS 26 and later, a frosted material
    /// before that.
    @ViewBuilder
    func glassPill() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
    }
}
