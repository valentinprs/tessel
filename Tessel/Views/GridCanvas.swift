import SwiftUI

struct GridCanvas: View {
    let photos: [SelectedPhoto]
    let layout: LayoutNode
    let spacing: CGFloat
    let margin: CGFloat
    let cornerRadius: CGFloat
    let backgroundColor: Color
    var usesThumbnails = false
    var highlightedSlot: Int?
    /// How each photo is framed, by photo id. Photos without one fill their
    /// cell, centred.
    var crops: [String: PhotoCrop] = [:]

    var body: some View {
        GeometryReader { proxy in
            let contentRect = Self.contentRect(in: proxy.size, margin: margin)
            let frames = layout.geometry(in: contentRect, spacing: spacing).frames

            ZStack(alignment: .topLeading) {
                backgroundColor

                // The first layout pass reports a zero size; drawing the cells
                // then would make them grow out of the top-left corner.
                if proxy.size.width > 0, proxy.size.height > 0 {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        if frames.indices.contains(index) {
                            photoCell(photo, size: frames[index].size, isHighlighted: highlightedSlot == index)
                                .offset(x: frames[index].minX, y: frames[index].minY)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .transaction { transaction in
                // Thumbnails appear inside animated screen and tab changes:
                // their cells must snap into place instead of morphing.
                if usesThumbnails {
                    transaction.animation = nil
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grid preview")
    }

    static func contentRect(in size: CGSize, margin: CGFloat) -> CGRect {
        let inset = min(max(margin, 0), max(0, min(size.width, size.height) / 2))
        return CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    }

    private func photoCell(_ photo: SelectedPhoto, size: CGSize, isHighlighted: Bool) -> some View {
        let crop = crops[photo.id] ?? PhotoCrop()
        let imageSize = photo.image.size
        let fill = PhotoCrop.fillSize(of: imageSize, in: size, scale: crop.scale)
        let shift = PhotoCrop.maximumShift(of: imageSize, in: size, scale: crop.scale)

        return Image(uiImage: usesThumbnails ? photo.thumbnail : photo.image)
            .resizable()
            .frame(width: fill.width, height: fill.height)
            .offset(x: crop.offset.x * shift.width, y: crop.offset.y * shift.height)
            .frame(width: size.width, height: size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            }
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.black.opacity(0.25))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(.white, lineWidth: 3)
                        }
                }
            }
            .accessibilityLabel("Photo")
    }
}

private struct DividerSnap: Equatable {
    let leadingWeight: CGFloat
    /// Where the divider sits along the whole line, shown while locked.
    let percent: Int
}

/// The preview canvas: drag the gaps between photos to resize them, drag or
/// pinch a photo to reframe it, hold a photo then tap another to swap them,
/// and tap to view the grid full screen.
struct EditableGridCanvas: View {
    @Binding var photos: [SelectedPhoto]
    @Binding var layout: GridLayout
    @Binding var crops: [String: PhotoCrop]
    let spacing: CGFloat
    let margin: CGFloat
    let background: Color
    /// Called right before a resize, swap or reset changes the grid.
    var onWillEdit: () -> Void = {}
    /// Called on a plain tap, when no photo is waiting to be swapped.
    var onTap: () -> Void = {}

    @State private var selectedSlot: Int?
    /// How the photo being reframed was framed when the gesture began.
    @State private var panStart: PhotoCrop?
    @State private var zoomStart: PhotoCrop?
    @State private var dragStartWeights: [CGFloat]?
    @State private var activeDividerID: String?
    @State private var snap: DividerSnap?

    private let handleThickness: CGFloat = 28
    /// Distance (in points) at which a divider is pulled onto an anchor, and
    /// the larger distance needed to pull it off again.
    private let snapDistance: CGFloat = 10
    private let releaseDistance: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let contentRect = GridCanvas.contentRect(in: proxy.size, margin: margin)
            let geometry = layout.root.geometry(in: contentRect, spacing: spacing)

            ZStack(alignment: .topLeading) {
                GridCanvas(
                    photos: photos,
                    layout: layout.root,
                    spacing: spacing,
                    margin: margin,
                    cornerRadius: 0,
                    backgroundColor: background,
                    highlightedSlot: selectedSlot,
                    crops: crops
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: tapOutsidePhotos)

                ForEach(Array(geometry.frames.enumerated()), id: \.offset) { slot, frame in
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        // The hold is tried first; a shorter press falls
                        // through to the tap.
                        .gesture(
                            LongPressGesture(minimumDuration: 0.3)
                                .onEnded { _ in selectPhoto(at: slot) }
                                .exclusively(before: TapGesture().onEnded { tapPhoto(at: slot) })
                        )
                        .simultaneousGesture(panGesture(slot: slot, cell: frame.size))
                        .simultaneousGesture(zoomGesture(slot: slot))
                        .accessibilityElement()
                        .accessibilityLabel("Photo \(slot + 1)")
                        .accessibilityHint("Touch and hold, then tap another photo to swap them.")
                        .accessibilityAction(named: "Select to swap") { selectPhoto(at: slot) }
                        .accessibilityAction(named: "Reset framing") { resetCrop(at: slot) }
                        .accessibilityAddTraits(.isButton)
                }

                ForEach(geometry.dividers) { divider in
                    dividerHandle(divider)
                }
            }
        }
        .sensoryFeedback(trigger: selectedSlot) { _, newSlot in
            newSlot != nil ? .impact(weight: .medium) : .selection
        }
        .sensoryFeedback(.alignment, trigger: snap) { _, newSnap in newSnap != nil }
        .onChange(of: layout.id) { _, _ in selectedSlot = nil }
    }

    private func dividerHandle(_ divider: LayoutDivider) -> some View {
        let isVerticalGap = divider.axis == .horizontal
        let isActive = activeDividerID == divider.id
        let hitArea = isVerticalGap
            ? CGSize(width: handleThickness, height: divider.rect.height)
            : CGSize(width: divider.rect.width, height: handleThickness)

        return ZStack {
            Capsule()
                .fill(isActive ? EditorPalette.accent : .white)
                .frame(
                    width: isVerticalGap ? 5 : min(36, divider.rect.width * 0.5),
                    height: isVerticalGap ? min(36, divider.rect.height * 0.5) : 5
                )
                .overlay { Capsule().stroke(.black.opacity(0.25), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.35), radius: 3)
                .scaleEffect(isActive ? 1.2 : 1)

            if isActive, let snap {
                Text("\(snap.percent)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EditorPalette.accent, in: Capsule())
                    .shadow(color: .black.opacity(0.35), radius: 4)
                    .fixedSize()
                    .offset(x: isVerticalGap ? 0 : 34, y: isVerticalGap ? -34 : 0)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: hitArea.width, height: hitArea.height)
        .contentShape(Rectangle())
        .position(x: divider.rect.midX, y: divider.rect.midY)
        .gesture(resizeGesture(for: divider))
        .onTapGesture(count: 2) { resetProportions(of: divider) }
        .onTapGesture(perform: tapOutsidePhotos)
        .animation(.snappy(duration: 0.18), value: isActive)
        .animation(.snappy(duration: 0.18), value: snap)
        .accessibilityElement()
        .accessibilityLabel("Divider")
        .accessibilityHint("Drag to resize the neighboring photos. Double-tap to even them out.")
    }

    private func resizeGesture(for divider: LayoutDivider) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let node = layout.root.node(at: divider.path)
                let start = dragStartWeights ?? node.weights
                if dragStartWeights == nil {
                    onWillEdit()
                    dragStartWeights = start
                    activeDividerID = divider.id
                    selectedSlot = nil
                }

                let translation = divider.axis == .horizontal
                    ? value.translation.width
                    : value.translation.height
                let total = start.reduce(0, +)
                guard divider.span > 0, total > 0 else { return }

                let pair = start[divider.index] + start[divider.index + 1]
                let minimum = min(total * 0.1, pair / 2)
                let freeLeading = min(
                    max(start[divider.index] + translation / divider.span * total, minimum),
                    pair - minimum
                )
                let newSnap = snapping(
                    freeLeading,
                    anchors: anchors(
                        for: divider.index,
                        in: start,
                        template: layout.template.node(at: divider.path).weights,
                        minimum: minimum
                    ),
                    pointsPerWeight: divider.span / total
                )
                snap = newSnap
                let leading = newSnap?.leadingWeight ?? freeLeading

                var weights = start
                weights[divider.index] = leading
                weights[divider.index + 1] = pair - leading
                layout.root.setWeights(weights, at: divider.path)
            }
            .onEnded { _ in
                dragStartWeights = nil
                activeDividerID = nil
                snap = nil
            }
    }

    /// Divider positions worth locking onto: the positions the dividers
    /// have in the original template (thirds for a line of three, fifths
    /// for a line of five…).
    private func anchors(
        for index: Int,
        in weights: [CGFloat],
        template: [CGFloat],
        minimum: CGFloat
    ) -> [DividerSnap] {
        let total = weights.reduce(0, +)
        let templateTotal = template.reduce(0, +)
        let before = weights[..<index].reduce(0, +)
        let pair = weights[index] + weights[index + 1]
        guard templateTotal > 0, template.count == weights.count else { return [] }

        var result: [DividerSnap] = []
        var templateOffset: CGFloat = 0
        for templateWeight in template.dropLast() {
            templateOffset += templateWeight
            let fraction = templateOffset / templateTotal
            let leading = fraction * total - before
            guard leading >= minimum, leading <= pair - minimum else { continue }
            result.append(
                DividerSnap(leadingWeight: leading, percent: Int((fraction * 100).rounded()))
            )
        }
        return result
    }

    private func snapping(
        _ leading: CGFloat,
        anchors: [DividerSnap],
        pointsPerWeight: CGFloat
    ) -> DividerSnap? {
        func distance(to anchor: DividerSnap) -> CGFloat {
            abs(anchor.leadingWeight - leading) * pointsPerWeight
        }

        if let snap, let current = anchors.first(where: { $0 == snap }), distance(to: current) < releaseDistance {
            return current
        }
        return anchors
            .filter { distance(to: $0) < snapDistance }
            .min { distance(to: $0) < distance(to: $1) }
    }

    private func resetProportions(of divider: LayoutDivider) {
        let original = layout.template.node(at: divider.path).weights
        onWillEdit()
        withAnimation(.snappy) {
            layout.root.setWeights(original, at: divider.path)
        }
    }

    // MARK: Framing

    /// Dragging a photo moves it inside its cell, never past its edges.
    private func panGesture(slot: Int, cell: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard let id = photoID(at: slot) else { return }
                let current = crops[id] ?? PhotoCrop()
                let start = panStart ?? current
                if panStart == nil {
                    onWillEdit()
                    panStart = start
                    selectedSlot = nil
                }

                let shift = PhotoCrop.maximumShift(
                    of: photos[slot].image.size,
                    in: cell,
                    scale: current.scale
                )
                var crop = current
                crop.offset = CGPoint(
                    x: shift.width > 0 ? clamped(start.offset.x + value.translation.width / shift.width) : 0,
                    y: shift.height > 0 ? clamped(start.offset.y + value.translation.height / shift.height) : 0
                )
                crops[id] = crop
            }
            .onEnded { _ in panStart = nil }
    }

    /// Pinching a photo zooms it in, from filling its cell up to 5×.
    private func zoomGesture(slot: Int) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let id = photoID(at: slot) else { return }
                let current = crops[id] ?? PhotoCrop()
                let start = zoomStart ?? current
                if zoomStart == nil {
                    onWillEdit()
                    zoomStart = start
                    selectedSlot = nil
                }

                var crop = current
                crop.scale = min(max(start.scale * value.magnification, 1), PhotoCrop.maximumScale)
                crops[id] = crop
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func resetCrop(at slot: Int) {
        guard let id = photoID(at: slot), crops[id] != nil else { return }
        onWillEdit()
        withAnimation(.snappy) {
            crops[id] = nil
        }
    }

    private func photoID(at slot: Int) -> String? {
        photos.indices.contains(slot) ? photos[slot].id : nil
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, -1), 1)
    }

    private func selectPhoto(at slot: Int) {
        withAnimation(.snappy) {
            selectedSlot = slot
        }
    }

    private func tapOutsidePhotos() {
        if selectedSlot != nil {
            withAnimation(.snappy) { selectedSlot = nil }
        } else {
            onTap()
        }
    }

    private func tapPhoto(at slot: Int) {
        guard let selected = selectedSlot else {
            onTap()
            return
        }

        if selected != slot, photos.indices.contains(selected), photos.indices.contains(slot) {
            onWillEdit()
            withAnimation(.snappy) {
                photos.swapAt(selected, slot)
            }
        }
        selectedSlot = nil
    }
}
