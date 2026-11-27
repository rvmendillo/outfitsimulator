import OutfitKit
import SwiftUI

/// Aspect-fit size of `content` inside `container`.
func aspectFitSize(_ content: CGSize, in container: CGSize) -> CGSize {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return .zero }
    let s = min(container.width / content.width, container.height / content.height)
    return CGSize(width: content.width * s, height: content.height * s)
}

// MARK: - Cut-out brush editor

/// Erase / restore brush over the original pixels.
struct CutoutEditor: View {
    let sourceImage: UIImage
    @Binding var mask: AlphaMask

    @State private var mode: AlphaMask.BrushMode = .erase
    @State private var brushSize: Double = 28
    @State private var undoStack: [AlphaMask] = []
    @State private var lastPoint: CGPoint?
    @State private var maskImage: UIImage?
    @State private var original: AlphaMask?

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let imageSize = CGSize(width: mask.width, height: mask.height)
                let fit = aspectFitSize(imageSize, in: geo.size)
                ZStack {
                    Checkerboard(squareSize: 9)
                    if mode == .restore {
                        Image(uiImage: sourceImage).resizable().opacity(0.28)
                    }
                    Image(uiImage: sourceImage)
                        .resizable()
                        .mask {
                            if let maskImage {
                                Image(uiImage: maskImage).resizable().luminanceToAlpha()
                            }
                        }
                }
                .frame(width: fit.width, height: fit.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in paint(at: value.location, viewSize: fit) }
                        .onEnded { _ in lastPoint = nil }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityIdentifier("cutout.canvas")
            }

            Picker("Brush", selection: $mode) {
                Label("Erase", systemImage: "eraser").tag(AlphaMask.BrushMode.erase)
                Label("Restore", systemImage: "paintbrush").tag(AlphaMask.BrushMode.restore)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Brand.secondaryInk)
                Slider(value: $brushSize, in: 8...90).tint(Brand.coral)
                Image(systemName: "circle.fill").font(.system(size: 20)).foregroundStyle(Brand.secondaryInk)
            }

            HStack(spacing: 12) {
                Button {
                    if let previous = undoStack.popLast() { mask = previous }
                } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.brandSecondary)
                    .disabled(undoStack.isEmpty)
                Button {
                    if let original {
                        pushUndo()
                        mask = original
                    }
                } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.brandSecondary)
                    .disabled(original == nil || original == mask)
            }
        }
        .onAppear {
            if original == nil { original = mask }
            refreshMaskImage()
        }
        .onChange(of: mask) { _, _ in refreshMaskImage() }
    }

    private func refreshMaskImage() {
        maskImage = mask.makeGrayscaleCGImage().map { UIImage(cgImage: $0) }
    }

    private func pushUndo() {
        undoStack.append(mask)
        if undoStack.count > 20 { undoStack.removeFirst() }
    }

    private func paint(at location: CGPoint, viewSize: CGSize) {
        guard viewSize.width > 0, mask.width > 0 else { return }
        let scale = Double(mask.width) / Double(viewSize.width)
        let point = CGPoint(x: Double(location.x) * scale, y: Double(location.y) * scale)
        let radius = brushSize / 2 * scale
        var updated = mask
        if let lastPoint {
            updated.paintStroke(from: lastPoint, to: point, radius: radius, mode: mode)
        } else {
            pushUndo()
            updated.paintDab(center: point, radius: radius, mode: mode)
        }
        mask = updated
        lastPoint = point
    }
}

// MARK: - Fit guides

/// Drag the fit guides (width line, hem) and see the effect on the avatar live.
struct FitGuideEditor: View {
    @EnvironmentObject private var model: AppModel
    let cutout: UIImage
    let imageSize: CGSize
    let category: GarmentCategory
    @Binding var anchors: GarmentAnchors

    private let previewID = UUID()

    var body: some View {
        VStack(spacing: 12) {
            Text(anchors.level.guideHint)
                .font(.subheadline)
                .foregroundStyle(Brand.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            if category == .bottom {
                Picker("Align", selection: Binding(get: { anchors.level }, set: { anchors.level = $0; anchors.source = .user })) {
                    Text("Waistband").tag(AnchorLevel.waist)
                    Text("Hips").tag(AnchorLevel.hips)
                }
                .pickerStyle(.segmented)
                Toggle("Full length (ends at the ankles)", isOn: Binding(get: { anchors.fitsLength }, set: { anchors.fitsLength = $0; anchors.source = .user }))
                    .font(.subheadline)
                    .tint(Brand.coral)
                    .accessibilityIdentifier("fit.fullLength")
            }

            HStack(spacing: 12) {
                guideCanvas
                previewCanvas
            }
            .frame(maxHeight: .infinity)

            Button {
                if let cg = cutout.cgImage, let mask = RGBABitmap(cgImage: cg)?.alphaMask {
                    anchors = AnchorEstimator.estimate(category: category, mask: mask)
                }
            } label: { Label("Auto-detect again", systemImage: "wand.and.stars") }
                .buttonStyle(.brandSecondary)
                .disabled(cutout.cgImage == nil)
        }
    }

    private var guideCanvas: some View {
        GeometryReader { geo in
            let fit = aspectFitSize(imageSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Checkerboard(squareSize: 8)
                Image(uiImage: cutout).resizable()
                // Width line
                Path { p in
                    p.move(to: point(anchors.left, fit))
                    p.addLine(to: point(anchors.right, fit))
                }
                .stroke(Brand.coral, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if category == .bottom && anchors.fitsLength {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: CGFloat(anchors.hemY) * fit.height))
                        p.addLine(to: CGPoint(x: fit.width, y: CGFloat(anchors.hemY) * fit.height))
                    }
                    .stroke(Brand.lilac, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    handle(color: Brand.lilac)
                        .gesture(DragGesture(coordinateSpace: .named("fitImage")).onChanged { v in
                            anchors.hemY = clamp(Double(v.location.y / max(fit.height, 1)), 0, 1)
                            anchors.source = .user
                        })
                        .accessibilityIdentifier("fit.hemHandle")
                        .position(x: fit.width / 2, y: CGFloat(anchors.hemY) * fit.height)
                }
                handle(color: Brand.coral)
                    .gesture(DragGesture(coordinateSpace: .named("fitImage")).onChanged { v in
                        anchors.left = normalized(v.location, fit)
                        anchors.source = .user
                    })
                    .accessibilityIdentifier("fit.leftHandle")
                    .position(point(anchors.left, fit))
                handle(color: Brand.coral)
                    .gesture(DragGesture(coordinateSpace: .named("fitImage")).onChanged { v in
                        anchors.right = normalized(v.location, fit)
                        anchors.source = .user
                    })
                    .accessibilityIdentifier("fit.rightHandle")
                    .position(point(anchors.right, fit))
            }
            .frame(width: fit.width, height: fit.height)
            .coordinateSpace(name: "fitImage")
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var previewCanvas: some View {
        let garment = Garment(id: previewID, name: "Preview", category: category, imageFile: "preview", imageSize: imageSize,
                              anchors: anchors, dominantColor: .white)
        let outfit = Outfit(name: "", items: [OutfitItem(garmentID: previewID)])
        let profile = model.profile
        let scene = SceneBuilder.build(avatar: AvatarModel(profile: profile.body), outfit: outfit, garments: [previewID: garment],
                                       face: profile.face, skinTone: profile.effectiveSkinTone)
        var images: [SceneLayer.Content: UIImage] = [.garment(previewID): cutout]
        if let face = profile.face, let faceImage = model.uiImage(face.imageFile) { images[.face] = faceImage }
        return OutfitCanvas(scene: scene, images: images, style: model.avatarStyle,
                            bodyRect: CanvasMapping.standardBodyRect(for: scene.avatar),
                            guides: [ProportionGuide(y: targetY(scene.avatar), label: "", color: Brand.coral)])
            .brandCard()
            .accessibilityIdentifier("fit.preview")
    }

    private func targetY(_ avatar: AvatarModel) -> Double {
        Double(GarmentFitter.target(for: category, level: anchors.level, avatar: avatar).midpoint.y)
    }

    private func handle(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(radius: 2)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func point(_ normalized: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    private func normalized(_ location: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: clamp(Double(location.x / max(size.width, 1)), 0, 1), y: clamp(Double(location.y / max(size.height, 1)), 0, 1))
    }
}

// MARK: - Sheets

/// Editor for a piece that has not been saved yet.
struct PieceEditorSheet: View {
    @ObservedObject var piece: ReviewPiece
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var mask: AlphaMask
    @State private var anchors: GarmentAnchors

    init(piece: ReviewPiece) {
        self.piece = piece
        _mask = State(initialValue: piece.mask)
        _anchors = State(initialValue: piece.anchors)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Mode", selection: $tab) {
                    Text("Clean up edges").tag(0)
                    Text("Fit guides").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 0 {
                    CutoutEditor(sourceImage: piece.sourceImage, mask: $mask)
                } else {
                    FitGuideEditor(cutout: cutoutImage, imageSize: CGSize(width: mask.width, height: mask.height),
                                   category: piece.category, anchors: $anchors)
                }
            }
            .padding(16)
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle(piece.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        piece.mask = mask
                        piece.anchors = anchors
                        dismiss()
                    }
                    .accessibilityIdentifier("editor.done")
                }
            }
        }
    }

    private var cutoutImage: UIImage {
        CutoutComposer.compose(source: piece.source, mask: mask).makeCGImage().map { UIImage(cgImage: $0) } ?? piece.sourceImage
    }
}

/// Editor for a garment already in the closet.
struct GarmentEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let garment: Garment
    var initialTab = 0

    @State private var tab = 0
    @State private var source: RGBABitmap?
    @State private var sourceImage: UIImage?
    @State private var mask: AlphaMask?
    @State private var anchors: GarmentAnchors
    @State private var isSaving = false

    init(garment: Garment, initialTab: Int = 0) {
        self.garment = garment
        self.initialTab = initialTab
        _anchors = State(initialValue: garment.anchors)
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Mode", selection: $tab) {
                    Text("Clean up edges").tag(0)
                    Text("Fit guides").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 0 {
                    if let sourceImage, mask != nil {
                        CutoutEditor(sourceImage: sourceImage, mask: Binding(get: { mask! }, set: { mask = $0 }))
                    } else {
                        Text("The original photo for this piece isn't available, so its edges can't be edited.")
                            .font(.subheadline).foregroundStyle(Brand.secondaryInk)
                            .frame(maxHeight: .infinity)
                    }
                } else if let cutout = currentCutout {
                    FitGuideEditor(cutout: cutout, imageSize: currentSize, category: garment.category, anchors: $anchors)
                }
            }
            .padding(16)
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle(garment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private var currentSize: CGSize {
        if let mask { return CGSize(width: mask.width, height: mask.height) }
        return garment.imageSize
    }

    private var currentCutout: UIImage? {
        if let source, let mask, source.width == mask.width, source.height == mask.height {
            return CutoutComposer.compose(source: source, mask: mask).makeCGImage().map { UIImage(cgImage: $0) }
        }
        return model.uiImage(garment.imageFile)
    }

    private func load() {
        guard source == nil,
              let sourceFile = garment.sourceFile, let maskFile = garment.maskFile,
              let sourceData = model.store.readBlob(named: sourceFile), let maskData = model.store.readBlob(named: maskFile),
              let sourceCG = ImageCodec.decode(data: sourceData), let maskCG = ImageCodec.decode(data: maskData),
              let bitmap = RGBABitmap(cgImage: sourceCG), let loadedMask = AlphaMask(grayscaleImage: maskCG),
              bitmap.width == loadedMask.width, bitmap.height == loadedMask.height else { return }
        source = bitmap
        sourceImage = UIImage(cgImage: sourceCG)
        mask = loadedMask
    }

    private func save() {
        isSaving = true
        Task {
            if let source, let mask {
                await model.updateGarmentMask(garment.id, source: source, mask: mask, anchors: anchors)
            } else if var updated = model.garment(garment.id) {
                updated.anchors = anchors.normalized
                model.updateGarment(updated)
            }
            isSaving = false
            dismiss()
        }
    }
}
