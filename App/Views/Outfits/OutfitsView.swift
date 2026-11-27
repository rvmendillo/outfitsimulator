import OutfitKit
import SwiftUI

struct OutfitsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showGenerator = false
    @State private var renaming: Outfit?
    @State private var newName = ""
    @State private var shareItem: IdentifiableImage?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if model.outfits.isEmpty {
                    EmptyStateView(
                        title: "No outfits yet",
                        message: model.garments.isEmpty
                            ? "Add some clothes first, then style them in the Studio or let us mix them for you."
                            : "Style one in the Studio, or let us mix your closet into fresh combinations.",
                        actionTitle: model.garments.isEmpty ? "Add clothes" : "Generate outfits",
                        actionIdentifier: "outfits.emptyAction"
                    ) {
                        if model.garments.isEmpty { model.selectedTab = .closet } else { showGenerator = true }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(model.outfits) { outfit in
                                OutfitCard(outfit: outfit)
                                    .onTapGesture { model.openInStudio(outfit) }
                                    .contextMenu {
                                        Button { model.openInStudio(outfit) } label: { Label("Open in Studio", systemImage: "figure.stand") }
                                        Button { newName = outfit.name; renaming = outfit } label: { Label("Rename", systemImage: "pencil") }
                                        Button { model.duplicateOutfit(outfit) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                        Button {
                                            if let image = model.renderImage(for: outfit) { shareItem = IdentifiableImage(image: image) }
                                        } label: { Label("Share", systemImage: "square.and.arrow.up") }
                                        Button(role: .destructive) { model.deleteOutfit(outfit) } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .accessibilityIdentifier("outfits.card")
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("Outfits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGenerator = true
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .disabled(model.garments.isEmpty)
                    .accessibilityIdentifier("outfits.generate")
                }
            }
            .sheet(isPresented: $showGenerator) {
                OutfitGeneratorView()
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: [item.image]) }
            .alert("Rename outfit", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let outfit = renaming { model.renameOutfit(outfit, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
}

struct OutfitCard: View {
    @EnvironmentObject private var model: AppModel
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OutfitPreview(outfit: outfit, bodyRect: CanvasMapping.standardBodyRect(for: model.avatar))
                .aspectRatio(0.62, contentMode: .fit)
                .background(Brand.blush.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(outfit.name).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink).lineLimit(1)
            Text("\(outfit.items.count) piece\(outfit.items.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(Brand.secondaryInk)
        }
        .padding(10)
        .brandCard()
        .contentShape(Rectangle())
    }
}

/// "Mix my closet": generates outfit suggestions, optionally around locked pieces.
struct OutfitGeneratorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var locked: Set<UUID> = []
    @State private var includeOuterwear = true
    @State private var includeAccessories = true
    @State private var seed: UInt64 = UInt64(Date().timeIntervalSince1970)
    @State private var saved: Set<[UUID]> = []
    /// Kept stable while the user saves suggestions (regenerated only on request).
    @State private var result = GeneratorResult(suggestions: [], missing: [])

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    private func regenerate() {
        result = model.generateOutfits(count: 8, locked: locked, includeOuterwear: includeOuterwear,
                                       includeAccessories: includeAccessories, seed: seed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Build around")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.garments.filter { $0.category.isCore || $0.category == .shoes || $0.category == .outerwear }) { garment in
                                Button {
                                    if locked.contains(garment.id) { locked.remove(garment.id) } else { locked.insert(garment.id) }
                                } label: {
                                    GarmentCard(garment: garment, isSelected: locked.contains(garment.id), compact: true)
                                        .frame(width: 70, height: 70)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("generator.lock")
                            }
                        }
                    }
                    Toggle("Layer outerwear", isOn: $includeOuterwear).tint(Brand.coral)
                    Toggle("Add accessories", isOn: $includeAccessories).tint(Brand.coral)

                    if result.suggestions.isEmpty {
                        Text(emptyMessage(result))
                            .font(.subheadline)
                            .foregroundStyle(Brand.secondaryInk)
                            .padding(.vertical, 30)
                            .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(result.suggestions.enumerated()), id: \.offset) { index, suggestion in
                                suggestionCard(suggestion, index: index)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .onAppear(perform: regenerate)
            .onChange(of: seed) { _, _ in regenerate() }
            .onChange(of: locked) { _, _ in regenerate() }
            .onChange(of: includeOuterwear) { _, _ in regenerate() }
            .onChange(of: includeAccessories) { _, _ in regenerate() }
            .navigationTitle("Mix my closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        seed &+= 7919
                    } label: { Label("Shuffle", systemImage: "shuffle") }
                    .accessibilityIdentifier("generator.shuffle")
                }
            }
        }
    }

    private func emptyMessage(_ result: GeneratorResult) -> String {
        if !result.missing.isEmpty {
            return "Add at least one \(result.missing.map { $0.displayName.lowercased() }.joined(separator: " and ")) to get suggestions."
        }
        return "No new combinations — every mix is already saved. Try unlocking pieces."
    }

    private func suggestionCard(_ suggestion: OutfitSuggestion, index: Int) -> some View {
        let outfit = previewOutfit(suggestion)
        let isSaved = saved.contains(suggestion.signature)
        return VStack(alignment: .leading, spacing: 8) {
            OutfitPreview(outfit: outfit, bodyRect: CanvasMapping.standardBodyRect(for: model.avatar))
                .aspectRatio(0.62, contentMode: .fit)
                .background(Brand.blush.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: Double(i) < suggestion.score * 5 - 0.25 ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(Brand.coral)
                }
                Text("harmony").font(.caption2).foregroundStyle(Brand.secondaryInk)
            }
            HStack(spacing: 8) {
                Button {
                    model.applyToStudio(garmentIDs: suggestion.garmentIDs)
                    model.selectedTab = .studio
                    dismiss()
                } label: { Image(systemName: "figure.stand") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Try on")
                Button {
                    model.saveSuggestion(suggestion, name: "Mix \(model.library.outfits.count + 1)")
                    saved.insert(suggestion.signature)
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "checkmark" : "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.coral)
                .disabled(isSaved)
                .accessibilityIdentifier("generator.save.\(index)")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .brandCard()
    }

    private func previewOutfit(_ suggestion: OutfitSuggestion) -> Outfit {
        var outfit = Outfit(name: "Suggestion")
        for id in suggestion.garmentIDs {
            if let g = model.garment(id) { outfit.add(g) { model.garment($0)?.category } }
        }
        return outfit
    }
}
