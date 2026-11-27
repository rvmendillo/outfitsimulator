import OutfitKit
import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selection: UUID?
    @State private var trayCategory: GarmentCategory?
    @State private var showGuides = false
    @State private var showSave = false
    @State private var outfitName = ""
    @State private var shareItem: IdentifiableImage?
    @State private var fitEditorGarment: Garment?
    @State private var shuffleSeed: UInt64 = 1

    // Gesture state
    @State private var dragStart: ItemAdjustment?
    @State private var pinchStart: ItemAdjustment?
    @State private var rotateStart: ItemAdjustment?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvasArea
                tray
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle(model.studio.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Save outfit", isPresented: $showSave) {
                TextField("Name", text: $outfitName)
                    .accessibilityIdentifier("studio.nameField")
                Button("Save") { model.saveStudio(name: outfitName) }
                    .accessibilityIdentifier("studio.confirmSave")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give this look a name.")
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }
            .sheet(item: $fitEditorGarment) { garment in
                GarmentEditorSheet(garment: garment, initialTab: 1)
            }
            .onChange(of: model.studio.id) { _, _ in selection = nil }
        }
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let scene = model.studioScene()
            let rect = CanvasMapping.standardBodyRect(for: scene.avatar)
            let mapping = CanvasMapping(bodyRect: rect, canvasSize: geo.size, padding: 0.04)
            ZStack(alignment: .top) {
                OutfitCanvas(scene: scene, images: model.layerImages(for: scene), style: model.avatarStyle,
                             selection: selection.map { .garment($0) }, bodyRect: rect,
                             guides: showGuides ? Guides.proportion(for: scene.avatar) : [])
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        select(at: value.location, scene: scene, mapping: mapping)
                    })
                    .simultaneousGesture(dragGesture(scene: scene, mapping: mapping))
                    .simultaneousGesture(pinchGesture)
                    .simultaneousGesture(rotateGesture)
                    .accessibilityIdentifier("studio.canvas")

                if model.studio.items.isEmpty {
                    hint("Tap clothes below to try them on", symbol: "hand.tap")
                } else if let selection, let garment = model.garment(selection) {
                    selectionBar(garment)
                } else if !model.profile.hasFace {
                    Button {
                        model.selectedTab = .me
                    } label: {
                        hint("Add your face in Me to see yourself", symbol: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    private func hint(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
            .padding(.top, 8)
    }

    private func selectionBar(_ garment: Garment) -> some View {
        HStack(spacing: 4) {
            Text(garment.name).font(.footnote.weight(.semibold)).lineLimit(1).padding(.leading, 10)
            Spacer(minLength: 4)
            barButton("arrow.up.square", "Bring forward") { model.moveLayer(garment.id, direction: 1) }
            barButton("arrow.down.square", "Send backward") { model.moveLayer(garment.id, direction: -1) }
            barButton("ruler", "Fit guides") { fitEditorGarment = garment }
            barButton("arrow.counterclockwise", "Reset position") { model.setAdjustment(.identity, for: garment.id) }
            barButton("xmark.circle", "Take off") {
                model.removeFromStudio(garment.id)
                selection = nil
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.selectionBar")
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 36, height: 32)
        }
        .accessibilityLabel(label)
    }

    private func select(at location: CGPoint, scene: OutfitScene, mapping: CanvasMapping) {
        let body = mapping.toBody(location)
        let hit = scene.hitTest(body) { layer, pixel in
            guard let mask = model.hitMask(for: layer.content) else { return 1 }
            let x = Int(Double(pixel.x) / Double(layer.imageSize.width) * Double(mask.width))
            let y = Int(Double(pixel.y) / Double(layer.imageSize.height) * Double(mask.height))
            guard x >= 0, y >= 0, x < mask.width, y < mask.height else { return 0 }
            return Double(mask[x, y]) / 255
        }
        if let hit, case let .garment(id) = hit.content {
            selection = selection == id ? nil : id
        } else {
            selection = nil
        }
    }

    private func dragGesture(scene: OutfitScene, mapping: CanvasMapping) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStart == nil {
                    if selection == nil { select(at: value.startLocation, scene: scene, mapping: mapping) }
                    guard let id = selection else { return }
                    dragStart = model.adjustment(for: id)
                }
                guard let id = selection, let start = dragStart else { return }
                var adjustment = start
                adjustment.offset = start.offset + CGPoint(x: Double(value.translation.width) / mapping.scale,
                                                           y: Double(value.translation.height) / mapping.scale)
                model.setAdjustment(adjustment, for: id)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let id = selection else { return }
                if pinchStart == nil { pinchStart = model.adjustment(for: id) }
                guard let start = pinchStart else { return }
                var adjustment = model.adjustment(for: id)
                adjustment.scale = start.scale * Double(value.magnification)
                model.setAdjustment(adjustment, for: id)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard let id = selection else { return }
                if rotateStart == nil { rotateStart = model.adjustment(for: id) }
                guard let start = rotateStart else { return }
                var adjustment = model.adjustment(for: id)
                adjustment.rotation = start.rotation + value.rotation.radians
                model.setAdjustment(adjustment, for: id)
            }
            .onEnded { _ in rotateStart = nil }
    }

    // MARK: Tray

    private var tray: some View {
        let categories = model.categoriesInCloset()
        let current = trayCategory.flatMap { categories.contains($0) ? $0 : nil } ?? categories.first
        return VStack(spacing: 10) {
            if categories.isEmpty {
                VStack(spacing: 10) {
                    Text("Your closet is empty").font(.headline)
                    Button("Add clothes") { model.selectedTab = .closet }
                        .buttonStyle(.brandPrimary)
                        .frame(maxWidth: 220)
                }
                .padding(.vertical, 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { category in
                            Button { trayCategory = category } label: {
                                Chip(title: category.pluralName, systemImage: CategoryIcon.symbol(for: category),
                                     isSelected: category == current)
                            }
                            .accessibilityIdentifier("tray.category.\(category.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.garments(in: current)) { garment in
                            Button {
                                model.toggleInStudio(garment)
                                selection = nil
                            } label: {
                                GarmentCard(garment: garment, isSelected: model.studio.contains(garment.id), compact: true)
                                    .frame(width: 84, height: 84)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tray.garment")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 92)
                if model.studio.hasTopAndBottom(in: model.library) {
                    Toggle(isOn: Binding(get: { model.studio.tuckedIn }, set: { model.setTuckedIn($0) })) {
                        Label("Tuck in top", systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Brand.coral)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("studio.tuck")
                }
            }
        }
        .padding(.vertical, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(Brand.card)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { model.newStudio(); selection = nil } label: { Label("New outfit", systemImage: "plus") }
                Toggle(isOn: $showGuides) { Label("Proportion guides", systemImage: "ruler") }
                Button { model.selectedTab = .me } label: { Label("Body & face settings", systemImage: "person.crop.circle") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("studio.menu")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                shuffle()
            } label: {
                Image(systemName: "dice")
            }
            .accessibilityLabel("Shuffle outfit")
            .accessibilityIdentifier("studio.shuffle")
            .disabled(model.garments.isEmpty)

            Button {
                if let image = model.renderImage(for: model.studio) { shareItem = IdentifiableImage(image: image) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share outfit")
            .disabled(model.studio.items.isEmpty)

            Button {
                outfitName = model.studioIsSaved ? model.studio.name : suggestedName()
                showSave = true
            } label: {
                Image(systemName: model.studioIsSaved && !model.studioHasChanges ? "checkmark.circle.fill" : "square.and.arrow.down")
            }
            .accessibilityLabel("Save outfit")
            .accessibilityIdentifier("studio.save")
            .disabled(model.studio.items.isEmpty)
        }
    }

    private func suggestedName() -> String {
        let names = model.studio.items.compactMap { model.garment($0.garmentID) }
            .filter { $0.category.isCore }
            .map { ColorNaming.name(for: $0.dominantColor) }
        let unique = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return unique.isEmpty ? "Outfit \(model.library.outfits.count + 1)" : unique.prefix(2).joined(separator: " & ") + " look"
    }

    private func shuffle() {
        shuffleSeed &+= 0x9E37_79B9
        let locked = Set(model.studio.items.compactMap { item -> UUID? in
            // Keep the piece the user selected, shuffle everything else.
            item.garmentID == selection ? item.garmentID : nil
        })
        let result = model.generateOutfits(count: 1, locked: locked, includeOuterwear: true, includeAccessories: false,
                                           seed: shuffleSeed ^ UInt64(Date().timeIntervalSince1970))
        if let suggestion = result.suggestions.first {
            model.applyToStudio(garmentIDs: suggestion.garmentIDs)
        } else if !result.missing.isEmpty {
            model.alert = AppAlert(title: "Add more clothes",
                                   message: "To shuffle outfits, add at least one \(result.missing.map { $0.displayName.lowercased() }.joined(separator: " and ")).")
        }
    }
}

extension Outfit {
    func hasTopAndBottom(in library: Library) -> Bool {
        let categories = Set(items.compactMap { library.garment($0.garmentID)?.category })
        return categories.contains(.top) && (categories.contains(.bottom) || categories.contains(.dress))
    }
}

extension UserProfile {
    var hasFace: Bool { face != nil }
}
