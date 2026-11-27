import OutfitKit
import SwiftUI

/// Height / body shape / build controls with a live, proportion-accurate preview.
struct BodySettingsEditor: View {
    @Binding var body_: BodyProfile
    var units: UnitSystem
    var face: FaceAsset?
    var faceImage: UIImage?
    var showPreview = true

    init(body: Binding<BodyProfile>, units: UnitSystem, face: FaceAsset? = nil, faceImage: UIImage? = nil, showPreview: Bool = true) {
        _body_ = body
        self.units = units
        self.face = face
        self.faceImage = faceImage
        self.showPreview = showPreview
    }

    var body: some View {
        VStack(spacing: 18) {
            if showPreview {
                let avatar = AvatarModel(profile: body_)
                let scene = SceneBuilder.build(avatar: avatar, outfit: Outfit(name: ""), garments: [:], face: face,
                                               skinTone: body_.skinToneOverride ?? face?.skinTone ?? BodyProfile.defaultSkinTone)
                ZStack(alignment: .topLeading) {
                    OutfitCanvas(scene: scene, images: faceImage.map { [SceneLayer.Content.face: $0] } ?? [:],
                                 style: AvatarStyle(skin: scene.skinTone), bodyRect: CanvasMapping.standardBodyRect(for: avatar),
                                 guides: Guides.proportion(for: avatar))
                    Text(String(format: "%.1f heads tall", avatar.headsTall))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.card))
                        .padding(8)
                        .accessibilityIdentifier("body.headsTall")
                }
                .frame(height: 300)
                .brandCard()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Height").font(.headline)
                    Spacer()
                    Text(HeightFormatter.string(fromCentimetres: body_.heightCM, units: units))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Brand.coral)
                        .accessibilityIdentifier("body.heightValue")
                }
                HStack(spacing: 12) {
                    Button { adjustHeight(-1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                        .accessibilityLabel("Decrease height")
                    Slider(value: $body_.heightCM, in: BodyProfile.heightRange, step: 1)
                        .accessibilityIdentifier("body.heightSlider")
                    Button { adjustHeight(1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Increase height")
                }
                .tint(Brand.coral)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Body shape").font(.headline)
                Picker("Body shape", selection: $body_.shape) {
                    ForEach(BodyShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("body.shape")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Build").font(.headline)
                    Spacer()
                    Text(buildLabel).font(.subheadline).foregroundStyle(Brand.secondaryInk)
                }
                Slider(value: $body_.build, in: BodyProfile.buildRange)
                    .tint(Brand.coral)
                    .accessibilityIdentifier("body.build")
            }
        }
    }

    private var buildLabel: String {
        switch body_.build {
        case ..<0.93: return "Slim"
        case ..<1.08: return "Regular"
        case ..<1.17: return "Broad"
        default: return "Full"
        }
    }

    private func adjustHeight(_ delta: Double) {
        let step = units == .imperial ? HeightFormatter.centimetresPerInch : 1
        body_.heightCM = clamp(body_.heightCM + delta * step, BodyProfile.heightRange.lowerBound, BodyProfile.heightRange.upperBound)
    }
}
