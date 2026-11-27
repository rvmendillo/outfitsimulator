import OutfitKit
import SwiftUI

struct GarmentDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let garmentID: UUID

    @State private var editorTab: Int?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let garment = model.garment(garmentID) {
                content(garment)
            } else {
                EmptyStateView(title: "Piece removed", message: "This piece is no longer in your closet.")
            }
        }
        .background(Brand.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ garment: Garment) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Checkerboard(squareSize: 12)
                    if let image = model.uiImage(garment.imageFile) {
                        Image(uiImage: image).resizable().scaledToFit().padding(20)
                    }
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous).strokeBorder(Brand.hairline))

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name", text: binding(garment, \.name))
                        .font(Brand.display(24))
                        .accessibilityIdentifier("detail.name")
                    Picker("Category", selection: binding(garment, \.category)) {
                        ForEach(GarmentCategory.closetOrder) { category in
                            Label(category.displayName, systemImage: CategoryIcon.symbol(for: category)).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack(spacing: 8) {
                        ForEach(Array((garment.palette.isEmpty ? [garment.dominantColor] : garment.palette).enumerated()), id: \.offset) { _, color in
                            VStack(spacing: 4) {
                                Circle().fill(Color(color)).frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(Brand.hairline))
                                Text(ColorNaming.name(for: color)).font(.caption2).foregroundStyle(Brand.secondaryInk)
                            }
                        }
                        Spacer()
                        Toggle(isOn: binding(garment, \.favorite)) {
                            Image(systemName: garment.favorite ? "heart.fill" : "heart")
                        }
                        .toggleStyle(.button)
                        .tint(Brand.coral)
                    }
                    TextField("Notes (fabric, size, where it's from…)", text: binding(garment, \.notes), axis: .vertical)
                        .lineLimit(2...5)
                        .font(.subheadline)
                }
                .padding(16)
                .brandCard()

                VStack(spacing: 10) {
                    Button {
                        model.toggleInStudio(garment)
                        model.selectedTab = .studio
                    } label: {
                        Label(model.studio.contains(garment.id) ? "In your Studio outfit" : "Wear in Studio", systemImage: "figure.stand")
                    }
                    .buttonStyle(.brandPrimary)
                    .disabled(model.studio.contains(garment.id))
                    .accessibilityIdentifier("detail.wear")

                    HStack(spacing: 10) {
                        Button { editorTab = 0 } label: { Label("Edges", systemImage: "wand.and.stars") }
                            .buttonStyle(.brandSecondary)
                            .accessibilityIdentifier("detail.editEdges")
                        Button { editorTab = 1 } label: { Label("Fit guides", systemImage: "ruler") }
                            .buttonStyle(.brandSecondary)
                            .accessibilityIdentifier("detail.editFit")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete piece", systemImage: "trash")
                    }
                    .padding(.top, 6)
                    .accessibilityIdentifier("detail.delete")
                }
            }
            .padding(16)
        }
        .sheet(item: Binding(get: { editorTab.map(EditorTab.init) }, set: { editorTab = $0?.value })) { tab in
            GarmentEditorSheet(garment: garment, initialTab: tab.value)
        }
        .confirmationDialog("Delete \(garment.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteGarment(garment.id)
                dismiss()
            }
        } message: {
            Text("It will also be removed from any outfits.")
        }
    }

    private struct EditorTab: Identifiable {
        let value: Int
        var id: Int { value }
    }

    private func binding<Value>(_ garment: Garment, _ keyPath: WritableKeyPath<Garment, Value>) -> Binding<Value> {
        Binding(
            get: { model.garment(garmentID)?[keyPath: keyPath] ?? garment[keyPath: keyPath] },
            set: { newValue in
                guard var current = model.garment(garmentID) else { return }
                if (keyPath as AnyKeyPath) == (\Garment.category as AnyKeyPath), let category = newValue as? GarmentCategory {
                    model.changeCategory(of: garmentID, to: category)
                    return
                }
                current[keyPath: keyPath] = newValue
                model.updateGarment(current)
            }
        )
    }
}
