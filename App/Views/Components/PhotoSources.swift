import PhotosUI
import SwiftUI
import UIKit

/// Bundled sample photos (Debug builds only; used by UI tests and demos).
enum SampleData {
    static func urls(prefix: String = "uitest-sample-") -> [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var isAvailable: Bool { !urls().isEmpty }

    static func data(named name: String) -> Data? {
        urls().first { $0.lastPathComponent.contains(name) }.flatMap { try? Data(contentsOf: $0) }
    }
}

/// Camera capture via `UIImagePickerController`.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Share sheet for exported images.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// "Photos / Camera / Samples" buttons that deliver image data.
struct PhotoSourcePicker: View {
    var allowsMultiple: Bool
    var sampleNames: [String]
    var onData: ([Data]) -> Void

    @State private var items: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $items, maxSelectionCount: allowsMultiple ? 10 : 1, matching: .images) {
                Label(allowsMultiple ? "Choose photos" : "Choose a photo", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.brandPrimary)
            .accessibilityIdentifier("source.photos")

            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                }
                .buttonStyle(.brandSecondary)
                .accessibilityIdentifier("source.camera")
            }

            if SampleData.isAvailable && !sampleNames.isEmpty {
                Button {
                    let data = sampleNames.compactMap(SampleData.data(named:))
                    if !data.isEmpty { onData(data) }
                } label: {
                    Label("Use sample photo", systemImage: "sparkles")
                }
                .buttonStyle(.brandSecondary)
                .accessibilityIdentifier("source.sample")
            }
            if isLoading { ProgressView().padding(.top, 4) }
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            isLoading = true
            Task {
                var result: [Data] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) { result.append(data) }
                }
                await MainActor.run {
                    isLoading = false
                    items = []
                    if !result.isEmpty { onData(result) }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.92) { onData([data]) }
            }
            .ignoresSafeArea()
        }
    }
}
