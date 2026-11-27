import OutfitKit
import SwiftUI

/// A detected piece being reviewed before it is saved.
@MainActor
final class ReviewPiece: ObservableObject, Identifiable {
    let id = UUID()
    let extracted: ExtractedPiece
    let source: RGBABitmap
    let sourceImage: UIImage
    let dominantColor: SRGBColor
    let palette: [SRGBColor]

    @Published var include = true
    @Published var name: String
    @Published var category: GarmentCategory {
        didSet {
            guard category != oldValue else { return }
            if anchors.source != .user { anchors = extracted.anchors(for: category) }
            if !nameEdited { name = "\(ColorNaming.name(for: dominantColor)) \(category.displayName)" }
        }
    }
    @Published var mask: AlphaMask {
        didSet { refreshPreview() }
    }
    @Published var anchors: GarmentAnchors
    @Published private(set) var preview: UIImage?
    var nameEdited = false

    init?(_ piece: ExtractedPiece) {
        guard let cg = piece.source.makeCGImage() else { return nil }
        extracted = piece
        source = piece.source
        sourceImage = UIImage(cgImage: cg)
        dominantColor = piece.dominantColor
        palette = piece.palette
        name = piece.name
        category = piece.category
        mask = piece.mask
        anchors = piece.anchors
        refreshPreview()
    }

    func refreshPreview() {
        preview = CutoutComposer.compose(source: source, mask: mask).makeCGImage().map { UIImage(cgImage: $0) }
    }
}

/// Add clothes: choose photos → separate pieces → review → save.
struct ImportFlowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case choose
        case processing(done: Int, total: Int)
        case review
        case saving
    }

    @State private var stage: Stage = .choose
    @State private var pieces: [ReviewPiece] = []
    @State private var notes: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose: chooseView
                case let .processing(done, total): processingView(done: done, total: total)
                case .review: ReviewPiecesView(pieces: pieces, notes: notes, onSave: save, onAddMore: { stage = .choose })
                case .saving:
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Brand.coral)
                        Text("Adding to your closet…").font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(stage == .saving)
                        .accessibilityIdentifier("import.cancel")
                }
            }
        }
        .interactiveDismissDisabled(stage != .choose)
    }

    private var title: String {
        switch stage {
        case .choose: return "Add clothes"
        case .processing: return "Separating pieces"
        case .review: return "Review pieces"
        case .saving: return "Saving"
        }
    }

    private var chooseView: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(spacing: 14) {
                    exampleCard(symbol: "figure.stand", title: "Worn outfit", text: "Full body, front-facing")
                    exampleCard(symbol: "square.grid.2x2", title: "Flat-lay", text: "Pieces on a plain surface")
                }
                .padding(.top, 8)
                Text("We'll find each top, bottom, dress, pair of shoes, hat, bag and more, and cut them out for you.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.secondaryInk)
                    .multilineTextAlignment(.center)
                PhotoSourcePicker(allowsMultiple: true, sampleNames: ["outfit", "flatlay"]) { data in
                    process(data)
                }
            }
            .padding(24)
        }
    }

    private func exampleCard(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Brand.coral)
            Text(title).font(.headline).foregroundStyle(Brand.ink)
            Text(text).font(.caption).foregroundStyle(Brand.secondaryInk).multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150)
        .brandCard()
    }

    private func processingView(done: Int, total: Int) -> some View {
        VStack(spacing: 18) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(Brand.coral)
                .frame(maxWidth: 240)
            Text("Separating pieces… \(min(done + 1, total)) of \(total)").font(.headline).foregroundStyle(Brand.ink)
            Text("Finding garments, refining edges and measuring fit points.")
                .font(.subheadline).foregroundStyle(Brand.secondaryInk).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("import.processing")
    }

    private func process(_ photos: [Data]) {
        stage = .processing(done: 0, total: photos.count)
        Task {
            var newPieces: [ReviewPiece] = []
            var newNotes: [String] = []
            for (index, data) in photos.enumerated() {
                do {
                    let result = try await model.engine.extractGarments(from: data)
                    let reviewed = await MainActor.run { result.pieces.compactMap(ReviewPiece.init) }
                    newPieces.append(contentsOf: reviewed)
                    if result.pieces.isEmpty {
                        newNotes.append("Photo \(index + 1): no clothing found. Try a plainer background or a full-body photo.")
                    }
                } catch {
                    newNotes.append("Photo \(index + 1): \(error.localizedDescription)")
                }
                await MainActor.run { stage = .processing(done: index + 1, total: photos.count) }
            }
            let hasParser = await model.engine.hasParser()
            if !hasParser {
                newNotes.append("Clothing recognition is unavailable in this build, so photos of people come out as one piece.")
            }
            await MainActor.run {
                pieces.append(contentsOf: newPieces)
                notes = newNotes
                stage = .review
            }
        }
    }

    private func save() {
        stage = .saving
        Task {
            let added = await model.addPieces(pieces)
            await MainActor.run {
                if added.isEmpty && pieces.contains(where: \.include) {
                    stage = .review
                } else {
                    dismiss()
                }
            }
        }
    }
}

struct ReviewPiecesView: View {
    let pieces: [ReviewPiece]
    let notes: [String]
    var onSave: () -> Void
    var onAddMore: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.blush))
                }
                if pieces.isEmpty {
                    EmptyStateView(title: "Nothing found", message: "We couldn't find clothing in these photos.",
                                   actionTitle: "Try other photos", action: onAddMore)
                } else {
                    Text("Untick anything you don't want. Tap a piece to clean up its edges or adjust how it fits.")
                        .font(.subheadline).foregroundStyle(Brand.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(pieces) { piece in
                        ReviewPieceRow(piece: piece)
                    }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if !pieces.isEmpty {
                ReviewSaveBar(pieces: pieces, onSave: onSave, onAddMore: onAddMore)
            }
        }
    }
}

private struct ReviewSaveBar: View {
    let pieces: [ReviewPiece]
    var onSave: () -> Void
    var onAddMore: () -> Void

    var body: some View {
        // Observe each piece's include flag through a lightweight count.
        IncludedCount(pieces: pieces) { count in
            HStack(spacing: 12) {
                Button("More photos", action: onAddMore)
                    .buttonStyle(.brandSecondary)
                    .frame(maxWidth: 150)
                Button(count == 1 ? "Add 1 piece" : "Add \(count) pieces", action: onSave)
                    .buttonStyle(.brandPrimary)
                    .disabled(count == 0)
                    .accessibilityIdentifier("import.save")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

/// Re-renders when any piece's `include` changes.
private struct IncludedCount<Content: View>: View {
    let pieces: [ReviewPiece]
    @ViewBuilder var content: (Int) -> Content
    @State private var count = 0

    var body: some View {
        content(count)
            .onAppear { recount() }
            .onReceive(NotificationCenter.default.publisher(for: .reviewPieceChanged)) { _ in recount() }
    }

    private func recount() { count = pieces.filter(\.include).count }
}

extension Notification.Name {
    static let reviewPieceChanged = Notification.Name("ReviewPieceChanged")
}

struct ReviewPieceRow: View {
    @ObservedObject var piece: ReviewPiece
    @State private var showEditor = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { showEditor = true } label: {
                ZStack {
                    Checkerboard(squareSize: 7)
                    if let preview = piece.preview {
                        Image(uiImage: preview).resizable().scaledToFit().padding(6)
                    }
                }
                .frame(width: 104, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.hairline))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Brand.coral))
                        .padding(6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(piece.name)")
            .accessibilityIdentifier("review.edit")

            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: Binding(get: { piece.name }, set: { piece.name = $0; piece.nameEdited = true }))
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("review.name")
                Menu {
                    Picker("Category", selection: $piece.category) {
                        ForEach(GarmentCategory.closetOrder) { category in
                            Label(category.displayName, systemImage: CategoryIcon.symbol(for: category)).tag(category)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        CategoryIcon(category: piece.category)
                        Text(piece.category.displayName)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Brand.blush))
                    .foregroundStyle(Brand.ink)
                }
                .accessibilityIdentifier("review.category")
                HStack(spacing: 4) {
                    ForEach(Array(piece.palette.prefix(3).enumerated()), id: \.offset) { _, color in
                        Circle().fill(Color(color)).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Brand.hairline))
                    }
                }
                Toggle("Add to closet", isOn: Binding(get: { piece.include }, set: {
                    piece.include = $0
                    NotificationCenter.default.post(name: .reviewPieceChanged, object: nil)
                }))
                .font(.subheadline)
                .tint(Brand.coral)
                .accessibilityIdentifier("review.include")
            }
        }
        .padding(12)
        .brandCard()
        .opacity(piece.include ? 1 : 0.55)
        .sheet(isPresented: $showEditor) {
            PieceEditorSheet(piece: piece)
        }
    }
}
