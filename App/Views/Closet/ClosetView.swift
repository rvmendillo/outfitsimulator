import OutfitKit
import SwiftUI

struct ClosetView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: GarmentCategory?
    @State private var showImport = false
    @State private var path = NavigationPath()

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.garments.isEmpty {
                    EmptyStateView(
                        title: "Your closet is empty",
                        message: "Add a photo of an outfit you're wearing, or clothes laid flat. We'll separate every piece for you.",
                        actionTitle: "Add clothes",
                        actionIdentifier: "closet.emptyAdd"
                    ) { showImport = true }
                } else {
                    content
                }
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add clothes")
                    .accessibilityIdentifier("closet.add")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                GarmentDetailView(garmentID: id)
            }
            .sheet(isPresented: $showImport) {
                ImportFlowView()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { filter = nil } label: { Chip(title: "All", isSelected: filter == nil) }
                            .accessibilityIdentifier("closet.filter.all")
                        ForEach(model.categoriesInCloset()) { category in
                            Button { filter = category } label: {
                                Chip(title: category.pluralName, systemImage: CategoryIcon.symbol(for: category), isSelected: filter == category)
                            }
                            .accessibilityIdentifier("closet.filter.\(category.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                let items = model.garments(in: filter)
                Text("\(items.count) piece\(items.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Brand.secondaryInk)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { garment in
                        NavigationLink(value: garment.id) {
                            GarmentCard(garment: garment)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("closet.garment")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
    }
}

struct GarmentCard: View {
    @EnvironmentObject private var model: AppModel
    let garment: Garment
    var isSelected = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Checkerboard(squareSize: 8)
                if let image = model.thumbnail(for: garment) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Brand.coral)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(compact ? 1 : 0.82, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Brand.coral : Brand.hairline, lineWidth: isSelected ? 2.5 : 1))
            if !compact {
                Text(garment.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(Color(garment.dominantColor)).frame(width: 8, height: 8)
                    Text(garment.category.displayName).font(.caption2).foregroundStyle(Brand.secondaryInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(garment.name), \(garment.category.displayName)")
    }
}
