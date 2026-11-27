import OutfitKit
import SwiftUI

/// Pick a selfie → cut out the head → check alignment and proportions → save.
struct FaceSetupView: View {
    @EnvironmentObject private var model: AppModel
    var showsSkip = false
    var onFinished: () -> Void

    private enum Stage {
        case choose
        case processing
        case review(HeadCutout, UIImage)
        case failed(String)
    }

    @State private var stage: Stage = .choose
    @State private var adjustment = ItemAdjustment.identity
    @State private var isSaving = false

    var body: some View {
        Group {
            switch stage {
            case .choose:
                chooseView
            case .processing:
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large).tint(Brand.coral)
                    Text("Finding your face and hair…").font(.headline).foregroundStyle(Brand.ink)
                    Text("Everything happens on your device.").font(.subheadline).foregroundStyle(Brand.secondaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("face.processing")
            case let .review(head, image):
                FaceAlignmentView(head: head, headImage: image, adjustment: $adjustment, isSaving: isSaving) {
                    save(head)
                } onRetake: {
                    adjustment = .identity
                    stage = .choose
                }
            case let .failed(message):
                VStack(spacing: 16) {
                    Image(systemName: "face.dashed").font(.system(size: 54)).foregroundStyle(Brand.coral)
                    Text("We couldn't use that photo").font(Brand.display(24)).foregroundStyle(Brand.ink)
                    Text(message).font(.body).foregroundStyle(Brand.secondaryInk).multilineTextAlignment(.center)
                    Button("Try another photo") { stage = .choose }
                        .buttonStyle(.brandPrimary)
                        .accessibilityIdentifier("face.retry")
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Brand.canvas.ignoresSafeArea())
    }

    private var chooseView: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Brand.blush).frame(width: 150, height: 150)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(Brand.coral)
                }
                .padding(.top, 24)
                Text("Add your face").font(Brand.display(30)).foregroundStyle(Brand.ink)
                Text("We cut out your face and hair and scale them to your height, so every outfit is shown in true proportion.")
                    .font(.body).foregroundStyle(Brand.secondaryInk).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 10) {
                    tip("face.smiling", "Look straight at the camera")
                    tip("sun.max", "Even light, no strong shadows")
                    tip("rectangle.dashed", "Plain background works best")
                    tip("eyeglasses", "Remove hats and sunglasses")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .brandCard()
                PhotoSourcePicker(allowsMultiple: false, sampleNames: ["face"]) { data in
                    if let first = data.first { process(first) }
                }
                if showsSkip {
                    Button("Skip for now") { onFinished() }
                        .font(.headline)
                        .foregroundStyle(Brand.secondaryInk)
                        .padding(.top, 4)
                        .accessibilityIdentifier("face.skip")
                }
            }
            .padding(24)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(Brand.ink)
    }

    private func process(_ data: Data) {
        stage = .processing
        Task {
            do {
                let head = try await model.engine.extractHead(from: data)
                guard let cg = head.image.makeCGImage() else { throw ImageError.encodingFailed }
                await MainActor.run {
                    adjustment = .identity
                    stage = .review(head, UIImage(cgImage: cg))
                }
            } catch {
                await MainActor.run { stage = .failed(error.localizedDescription) }
            }
        }
    }

    private func save(_ head: HeadCutout) {
        isSaving = true
        Task {
            await model.setFace(head, adjustment: adjustment)
            await MainActor.run {
                isSaving = false
                onFinished()
            }
        }
    }
}

/// Shows the cut-out head on the avatar with proportion guides and fine-tuning.
struct FaceAlignmentView: View {
    @EnvironmentObject private var model: AppModel
    let head: HeadCutout
    let headImage: UIImage
    @Binding var adjustment: ItemAdjustment
    var isSaving: Bool
    var onSave: () -> Void
    var onRetake: () -> Void

    @State private var showFullBody = false

    private var face: FaceAsset {
        FaceAsset(imageFile: "preview", imageSize: head.size, eyeLeft: head.eyeLeft, eyeRight: head.eyeRight, chin: head.chin,
                  skinTone: head.skinTone, adjustment: adjustment)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SectionHeader(title: "Check the fit", subtitle: "Your head is scaled to \(HeightFormatter.string(fromCentimetres: model.profile.body.heightCM, units: model.profile.units)) — the dashed lines show where eyes and chin belong.")
                preview
                Picker("View", selection: $showFullBody) {
                    Text("Head & shoulders").tag(false)
                    Text("Full body").tag(true)
                }
                .pickerStyle(.segmented)

                ForEach(head.warnings, id: \.message) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Brand.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.blush))
                }

                fineTune

                Button {
                    onSave()
                } label: {
                    if isSaving { ProgressView().tint(.white) } else { Text("Use this face") }
                }
                .buttonStyle(.brandPrimary)
                .disabled(isSaving)
                .accessibilityIdentifier("face.save")

                Button("Choose a different photo", action: onRetake)
                    .buttonStyle(.brandSecondary)
                    .accessibilityIdentifier("face.retake")
            }
            .padding(20)
        }
    }

    private var preview: some View {
        let avatar = model.avatar
        let scene = SceneBuilder.build(avatar: avatar, outfit: Outfit(name: ""), garments: [:], face: face, skinTone: head.skinTone)
        let rect = showFullBody
            ? CanvasMapping.standardBodyRect(for: avatar)
            : CGRect(x: -0.2, y: -0.05, width: 0.4, height: avatar.shoulderY + 0.12)
        return OutfitCanvas(scene: scene, images: [.face: headImage], style: AvatarStyle(skin: head.skinTone),
                            bodyRect: rect, guides: showFullBody ? Guides.proportion(for: avatar) : Guides.head(for: avatar))
            .frame(height: 380)
            .brandCard()
            .accessibilityIdentifier("face.preview")
    }

    private var fineTune: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fine-tune").font(.headline)
                Spacer()
                Button("Reset") { adjustment = .identity }
                    .font(.subheadline.weight(.semibold))
                    .disabled(adjustment.isIdentity)
            }
            slider("Size", value: Binding(get: { adjustment.scale }, set: { adjustment.scale = $0 }), range: 0.85...1.15)
            slider("Up / down", value: Binding(get: { Double(adjustment.offset.y) }, set: { adjustment.offset.y = $0 }), range: -0.03...0.03)
            slider("Left / right", value: Binding(get: { Double(adjustment.offset.x) }, set: { adjustment.offset.x = $0 }), range: -0.03...0.03)
            slider("Tilt", value: Binding(get: { adjustment.rotation }, set: { adjustment.rotation = $0 }), range: -0.18...0.18)
        }
        .padding(16)
        .brandCard()
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(width: 96, alignment: .leading)
            Slider(value: value, in: range).tint(Brand.coral)
        }
    }
}
