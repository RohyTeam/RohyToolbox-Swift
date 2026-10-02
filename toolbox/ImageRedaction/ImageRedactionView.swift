//
//  ImageRedactionView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Photos
import SwiftUI

struct ImageRedactionView: View {
    let asset: PHAsset

    @State private var image: UIImage?
    @State private var blocks: [TextBlock] = []
    @State private var state = RedactionState()
    @State private var mode: RedactionMode = .block
    @State private var blockColor = Color.accentColor
    @State private var exportFormat: ExportFormat = .original
    @State private var showsClearConfirmation = false

    @State private var canvasSize = CGSize.zero
    /// Pinch-to-zoom state (zooms around the content center).
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1
    @State private var wordPicker: TextBlock?
    @State private var selectedWords: Set<Int> = []
    /// The box currently being adjusted after a drag-create; tapping it
    /// finishes the creation.
    @State private var pendingBoxID: UUID?
    @State private var createOrigin: CGPoint?
    @State private var gestureMachine = BoxGestureStateMachine()
    /// Edge-resize state for the pending box.
    @State private var activeEdge: BoxEdge?
    @State private var edgeStartRect: CGRect?

    @State private var shareItems: [Any]?
    @State private var shareThenDelete = false
    @State private var exportFileURL: URL?
    @State private var showExporter = false

    private var originalFormatName: String {
        guard let resource = PHAssetResource.assetResources(for: asset).first else { return "JPG" }
        switch resource.uniformTypeIdentifier {
        case "public.png": return "PNG"
        case "public.heic": return "HEIC"
        default: return "JPG"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if let image {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                        // Boxes live in content coordinates so they zoom with
                        // the image.
                        boxesOverlay
                    }
                    .scaleEffect(zoomScale)
                } else {
                    ProgressView()
                }
            }
            // Gestures live on the container so their coordinates share the
            // same space as imageFrame() used for hit-testing and overlay
            // placement.
            .contentShape(Rectangle())
            .gesture(canvasGesture)
            .simultaneousGesture(magnifyGesture)
            .accessibilityIdentifier("redaction-canvas")
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newValue in canvasSize = newValue }
        }
        .overlay(alignment: .center) {
            wordPickerOverlay
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    state.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    state.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)
            }
            ToolbarItem(placement: .topBarTrailing) {
                exportMenu
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    autoRedact()
                } label: {
                    Label("Auto Redact", systemImage: "apple.intelligence")
                }
                .disabled(blocks.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(state.boxes.isEmpty)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    ForEach(RedactionMode.allCases) { candidate in
                        Button {
                            mode = candidate
                        } label: {
                            Label(candidate.name, systemImage: candidate.icon)
                        }
                    }
                } label: {
                    Label("Redaction Mode", systemImage: mode.icon)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                ColorPicker("Block Color", selection: $blockColor)
                    .labelsHidden()
                    .disabled(mode != .block)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // Watermark settings: not implemented yet.
                } label: {
                    Label("Watermark", systemImage: "drop")
                }
                .disabled(true)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ActivityPresenter(items: shareItems ?? []) { completed in
                if completed && shareThenDelete {
                    Task {
                        try? await PhotoSaver.delete(asset)
                    }
                }
                shareItems = nil
            }
        }
        .sheet(isPresented: $showExporter) {
            if let exportFileURL {
                FileExporter(fileURL: exportFileURL)
            }
        }
        .alert("Clear all redactions?", isPresented: $showsClearConfirmation) {
            Button("Clear All", role: .destructive) {
                state.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Export

    private var exportMenu: some View {
        Menu {
            Button {
                share(deleteAfter: false)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                share(deleteAfter: true)
            } label: {
                Label("Share & Delete", systemImage: "square.and.arrow.up.on.square")
            }
            Divider()
            Button {
                save(overwrite: true)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down.fill")
            }
            Button {
                save(overwrite: false)
            } label: {
                Label("Save Copy", systemImage: "doc.on.doc")
            }
            Button {
                saveToFiles()
            } label: {
                Label("Save to Files", systemImage: "folder")
            }
            Divider()
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        exportFormat = format
                    } label: {
                        if format == exportFormat {
                            Label(format.name(originalName: originalFormatName), systemImage: "checkmark")
                        } else {
                            Text(format.name(originalName: originalFormatName))
                        }
                    }
                }
            } label: {
                Label("Format", systemImage: "photo")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private func renderedData() -> Data? {
        guard let image else { return nil }
        return RedactionRenderer.data(
            image: image, boxes: state.boxes,
            format: exportFormat, originalUTI: originalUTI
        )
    }

    private var originalUTI: String {
        PHAssetResource.assetResources(for: asset).first?.uniformTypeIdentifier ?? "public.jpeg"
    }

    private func share(deleteAfter: Bool) {
        guard let image else { return }
        let rendered = RedactionRenderer.render(image: image, boxes: state.boxes)
        shareThenDelete = deleteAfter
        shareItems = [rendered]
    }

    private func save(overwrite: Bool) {
        guard let image else { return }
        let rendered = RedactionRenderer.render(image: image, boxes: state.boxes)
        Task {
            if overwrite, let data = renderedData() {
                try? await PhotoSaver.overwrite(asset: asset, data: data)
            } else {
                try? await PhotoSaver.saveCopy(image: rendered)
            }
        }
    }

    private func saveToFiles() {
        guard let data = renderedData() else { return }
        let ext: String
        switch exportFormat {
        case .png: ext = "png"
        case .jpeg: ext = "jpg"
        case .original: ext = originalFormatName.lowercased()
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("redacted.\(ext)")
        try? data.write(to: url)
        exportFileURL = url
        showExporter = true
    }

    // MARK: - Loading & analysis

    private func loadImage() async {
        guard let loaded = await Self.fullImage(for: asset) else { return }
        let normalized = Self.normalized(loaded)
        image = normalized
        blocks = await TextAnalyzer().analyze(normalized)
    }

    private static func fullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data.flatMap(UIImage.init(data:)))
            }
        }
    }

    /// Bakes EXIF orientation into the pixel buffer.
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - Canvas geometry

    private func imageFrame() -> CGRect {
        guard let image, canvasSize != .zero else { return .zero }
        let scale = min(
            canvasSize.width / image.size.width,
            canvasSize.height / image.size.height
        )
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Content space is the untransformed canvas; overlay positions are
    /// content coordinates so boxes zoom with the image. Gesture points are
    /// container coordinates and must be un-zoomed first.
    private func contentPoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x / zoomScale + canvasSize.width * (1 - 1 / zoomScale) / 2,
            y: canvasPoint.y / zoomScale + canvasSize.height * (1 - 1 / zoomScale) / 2
        )
    }

    private func toView(_ normalized: CGRect) -> CGRect {
        let frame = imageFrame()
        return CGRect(
            x: frame.minX + normalized.minX * frame.width,
            y: frame.minY + normalized.minY * frame.height,
            width: normalized.width * frame.width,
            height: normalized.height * frame.height
        )
    }

    private func toNormalized(_ canvasPoint: CGPoint) -> CGPoint {
        let point = contentPoint(from: canvasPoint)
        let frame = imageFrame()
        return CGPoint(
            x: (point.x - frame.minX) / frame.width,
            y: (point.y - frame.minY) / frame.height
        )
    }

    private func boxAt(_ canvasPoint: CGPoint) -> RedactionBox? {
        let point = contentPoint(from: canvasPoint)
        return state.boxes.last { toView($0.rect).contains(point) }
    }

    private func blockAt(_ canvasPoint: CGPoint) -> TextBlock? {
        let point = contentPoint(from: canvasPoint)
        return blocks.last { toView($0.rect).contains(point) }
    }

    // MARK: - Gestures

    /// Pinch-to-zoom around the content center.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = min(max(lastZoomScale * value.magnification, 1), 8)
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
            }
    }

    /// One gesture for everything; the timing/threshold logic lives in
    /// BoxGestureStateMachine (unit-tested), this just forwards actions.
    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeEdge == nil, !gestureMachine.isTouching {
                    // Detect the edge once per touch: the machine is not fed
                    // during an edge resize, so this branch re-runs per event
                    // otherwise.
                    activeEdge = pendingEdge(at: value.startLocation)
                    if activeEdge != nil {
                        edgeStartRect = pendingBoxID.flatMap { id in
                            state.boxes.first { $0.id == id }?.rect
                        }
                    }
                }
                if let edge = activeEdge {
                    applyEdgeResize(edge, translation: value.translation)
                    return
                }
                switch gestureMachine.touchChanged(
                    startLocation: value.startLocation,
                    location: value.location,
                    translation: value.translation
                ) {
                case .beginBox(let origin):
                    let box = RedactionBox(
                        rect: CGRect(origin: toNormalized(origin), size: .zero),
                        mode: mode, color: blockColor
                    )
                    state.add(box)
                    pendingBoxID = box.id
                    createOrigin = origin
                case .resizeBox(let point):
                    resizeCreating(to: point)
                default:
                    break
                }
            }
            .onEnded { value in
                if activeEdge != nil {
                    // A no-movement touch on an edge still counts as a tap.
                    if hypot(value.translation.width, value.translation.height) < 4 {
                        handleTap(at: value.startLocation)
                    }
                    activeEdge = nil
                    edgeStartRect = nil
                    return
                }
                switch gestureMachine.touchEnded(
                    location: value.location,
                    translation: value.translation
                ) {
                case .tap(let point):
                    handleTap(at: point)
                case .openWordPicker(let point):
                    if let block = blockAt(point) {
                        selectedWords = []
                        wordPicker = block
                    }
                case .finishBox:
                    // Creation finished; the box stays adjustable until tapped.
                    createOrigin = nil
                default:
                    break
                }
            }
    }

    private func handleTap(at point: CGPoint) {
        if pendingBoxID != nil {
            // Tapping the pending box finishes its creation.
            pendingBoxID = nil
            return
        }
        if let box = boxAt(point) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            state.remove(id: box.id)
            return
        }
        if let block = blockAt(point) {
            redact(block: block)
        }
    }

    private func resizeCreating(to current: CGPoint) {
        guard let id = pendingBoxID, let origin = createOrigin else { return }
        let from = toNormalized(origin)
        let to = toNormalized(current)
        state.update(id: id, rect: CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        ))
    }

    // MARK: - Pending box edge resize

    private enum BoxEdge {
        case left, right, top, bottom
    }

    /// The pending box's edge under the point, if any.
    private func pendingEdge(at canvasPoint: CGPoint) -> BoxEdge? {
        guard let id = pendingBoxID,
              let box = state.boxes.first(where: { $0.id == id }) else { return nil }
        let point = contentPoint(from: canvasPoint)
        let rect = toView(box.rect)
        let threshold: CGFloat = 24
        guard point.x > rect.minX - threshold, point.x < rect.maxX + threshold,
              point.y > rect.minY - threshold, point.y < rect.maxY + threshold else { return nil }
        let distances: [(BoxEdge, CGFloat)] = [
            (.left, abs(point.x - rect.minX)),
            (.right, abs(point.x - rect.maxX)),
            (.top, abs(point.y - rect.minY)),
            (.bottom, abs(point.y - rect.maxY)),
        ]
        return distances.min { $0.1 < $1.1 }?.0
    }

    private func applyEdgeResize(_ edge: BoxEdge, translation: CGSize) {
        guard let id = pendingBoxID, let start = edgeStartRect else { return }
        let frame = imageFrame()
        let dx = translation.width / frame.width
        let dy = translation.height / frame.height
        var rect = start
        let minSize: CGFloat = 0.01
        switch edge {
        case .left:
            let newMinX = min(start.minX + dx, start.maxX - minSize)
            rect = CGRect(x: newMinX, y: start.minY,
                          width: start.maxX - newMinX, height: start.height)
        case .right:
            rect.size.width = max(minSize, start.width + dx)
        case .top:
            let newMinY = min(start.minY + dy, start.maxY - minSize)
            rect = CGRect(x: start.minX, y: newMinY,
                          width: start.width, height: start.maxY - newMinY)
        case .bottom:
            rect.size.height = max(minSize, start.height + dy)
        }
        state.update(id: id, rect: rect)
    }

    // MARK: - Redaction actions

    /// Expands a rect slightly so text edges don't peek out, clamped to the
    /// normalized image bounds.
    private func inflated(_ rect: CGRect) -> CGRect {
        let margin = rect.height * 0.15
        return rect
            .insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func redact(block: TextBlock) {
        state.add(RedactionBox(rect: inflated(block.rect), mode: mode, color: blockColor))
    }

    private func redact(wordsOf block: TextBlock, selected: Set<Int>) {
        let words = block.words()
        for index in selected where words.indices.contains(index) {
            state.add(RedactionBox(rect: inflated(words[index].rect), mode: mode, color: blockColor))
        }
    }

    private func autoRedact() {
        for block in blocks where block.isSensitive {
            state.add(RedactionBox(rect: block.rect, mode: mode, color: blockColor))
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var wordPickerOverlay: some View {
        if let wordPicker {
            WordPickerPanel(
                block: wordPicker,
                selected: $selectedWords,
                onConfirm: {
                    redact(wordsOf: wordPicker, selected: selectedWords)
                    self.wordPicker = nil
                },
                onCancel: { self.wordPicker = nil }
            )
        }
    }

    private var boxesOverlay: some View {
        ForEach(state.boxes) { box in
            let rect = toView(box.rect)
            RedactionBoxView(
                box: box,
                viewRect: rect,
                image: image,
                isPending: box.id == pendingBoxID
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("redaction-box")
            .accessibilityIdentifier("redaction-box")
            .position(x: rect.midX, y: rect.midY)
        }
    }
}

/// One redaction box in the overlay. Blur/mosaic render the real effect
/// through the same pipeline the export renderer uses.
private struct RedactionBoxView: View {
    let box: RedactionBox
    let viewRect: CGRect
    let image: UIImage?
    let isPending: Bool

    @State private var patch: UIImage?

    private struct PatchKey: Hashable {
        var rect: CGRect
        var mode: RedactionMode
        var pending: Bool
    }

    var body: some View {
        ZStack {
            switch box.mode {
            case .block:
                box.color
            case .blur, .mosaic:
                if let patch {
                    Image(uiImage: patch)
                        .resizable()
                } else {
                    Color.gray.opacity(0.4)
                }
            }
            if isPending {
                // Dashed border while the box is still being adjusted.
                Rectangle()
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
            }
        }
        .frame(width: viewRect.width, height: viewRect.height)
        .task(id: PatchKey(rect: box.rect, mode: box.mode, pending: isPending)) {
            guard box.mode != .block, let image, !isPending else {
                patch = nil
                return
            }
            patch = await Task.detached(priority: .userInitiated) {
                RedactionRenderer.effectPatch(image: image, normalizedRect: box.rect, mode: box.mode)
            }.value
        }
    }
}
