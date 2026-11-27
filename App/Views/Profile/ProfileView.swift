import OutfitKit
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @State private var body_ = BodyProfile()
    @State private var showFaceSetup = false
    @State private var showFaceTune = false
    @State private var confirmErase = false
    @State private var useCustomSkin = false
    @State private var customSkin = Color(BodyProfile.defaultSkinTone)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    faceCard
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Proportions", subtitle: "Clothes and your face are scaled to these measurements.")
                        Picker("Units", selection: Binding(get: { model.profile.units }, set: { model.setUnits($0) })) {
                            Text("cm").tag(UnitSystem.metric)
                            Text("ft / in").tag(UnitSystem.imperial)
                        }
                        .pickerStyle(.segmented)
                        BodySettingsEditor(body: $body_, units: model.profile.units, face: model.profile.face,
                                           faceImage: model.uiImage(model.profile.face?.imageFile))
                    }
                    .padding(16)
                    .brandCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Avatar")
                        Toggle("Use a custom skin tone", isOn: $useCustomSkin).tint(Brand.coral)
                        if useCustomSkin {
                            ColorPicker("Skin tone", selection: $customSkin, supportsOpacity: false)
                        } else {
                            HStack {
                                Text("Skin tone").font(.subheadline)
                                Spacer()
                                Circle().fill(Color(model.skinTone)).frame(width: 24, height: 24)
                                Text(model.profile.face == nil ? "Default" : "From your photo")
                                    .font(.caption).foregroundStyle(Brand.secondaryInk)
                            }
                        }
                        Toggle("Show arms", isOn: $body_.showArms).tint(Brand.coral)
                        Toggle("Base layer under clothes", isOn: $body_.showBaseLayer).tint(Brand.coral)
                    }
                    .padding(16)
                    .brandCard()

                    aboutCard
                }
                .padding(16)
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("Me")
            .onAppear(perform: syncFromModel)
            .onChange(of: body_) { _, newValue in
                if newValue != model.profile.body { model.updateBody(newValue) }
            }
            .onChange(of: useCustomSkin) { _, enabled in
                body_.skinToneOverride = enabled ? SRGBColor(customSkin) : nil
            }
            .onChange(of: customSkin) { _, color in
                if useCustomSkin { body_.skinToneOverride = SRGBColor(color) }
            }
            .sheet(isPresented: $showFaceSetup) {
                FaceSetupView { showFaceSetup = false }
            }
            .sheet(isPresented: $showFaceTune) {
                FaceTuneSheet()
            }
            .confirmationDialog("Delete everything?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Delete all clothes, outfits and photos", role: .destructive) {
                    model.eraseAll()
                    syncFromModel()
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func syncFromModel() {
        body_ = model.profile.body
        useCustomSkin = model.profile.body.skinToneOverride != nil
        if let override = model.profile.body.skinToneOverride { customSkin = Color(override) }
    }

    private var faceCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Brand.blush)
                if let face = model.profile.face, let image = model.uiImage(face.imageFile) {
                    Image(uiImage: image).resizable().scaledToFit().padding(6).clipShape(Circle())
                } else {
                    Image(systemName: "person.fill").font(.system(size: 38)).foregroundStyle(Brand.coral)
                }
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.profile.face == nil ? "Add your face" : "Your face")
                    .font(Brand.display(22)).foregroundStyle(Brand.ink)
                Text(model.profile.face == nil ? "See outfits on you, in true proportion." : "Scaled to \(HeightFormatter.string(fromCentimetres: model.profile.body.heightCM, units: model.profile.units)).")
                    .font(.footnote).foregroundStyle(Brand.secondaryInk)
                HStack(spacing: 8) {
                    Button(model.profile.face == nil ? "Add photo" : "Change") { showFaceSetup = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.coral)
                        .accessibilityIdentifier("profile.face")
                    if model.profile.face != nil {
                        Button("Fine-tune") { showFaceTune = true }
                            .buttonStyle(.bordered)
                        Button(role: .destructive) { model.removeFace() } label: { Image(systemName: "trash") }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Remove face photo")
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .brandCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppIconTile(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Wordmark(size: 20)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption).foregroundStyle(Brand.secondaryInk)
                }
            }
            Label("Your photos are processed on this iPhone and never uploaded.", systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(Brand.ink)
            NavigationLink {
                LicensesView()
            } label: {
                Label("Acknowledgements", systemImage: "doc.text")
            }
            Button(role: .destructive) { confirmErase = true } label: {
                Label("Delete all data", systemImage: "trash")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard()
    }
}

/// Adjusts the saved face placement.
struct FaceTuneSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var adjustment = ItemAdjustment.identity

    var body: some View {
        NavigationStack {
            Group {
                if let face = model.profile.face, let image = model.uiImage(face.imageFile) {
                    ScrollView {
                        VStack(spacing: 16) {
                            let avatar = model.avatar
                            let scene = SceneBuilder.build(avatar: avatar, outfit: Outfit(name: ""), garments: [:],
                                                           face: tuned(face), skinTone: model.skinTone)
                            OutfitCanvas(scene: scene, images: [.face: image], style: model.avatarStyle,
                                         bodyRect: CGRect(x: -0.2, y: -0.05, width: 0.4, height: avatar.shoulderY + 0.12),
                                         guides: Guides.head(for: avatar))
                                .frame(height: 360)
                                .brandCard()
                            tuneSlider("Size", value: Binding(get: { adjustment.scale }, set: { adjustment.scale = $0 }), range: 0.85...1.15)
                            tuneSlider("Up / down", value: Binding(get: { Double(adjustment.offset.y) }, set: { adjustment.offset.y = $0 }), range: -0.03...0.03)
                            tuneSlider("Left / right", value: Binding(get: { Double(adjustment.offset.x) }, set: { adjustment.offset.x = $0 }), range: -0.03...0.03)
                            tuneSlider("Tilt", value: Binding(get: { adjustment.rotation }, set: { adjustment.rotation = $0 }), range: -0.18...0.18)
                            Button("Reset to automatic") { adjustment = .identity }
                                .buttonStyle(.brandSecondary)
                        }
                        .padding(16)
                    }
                } else {
                    EmptyStateView(title: "No face photo", message: "Add a face photo first.")
                }
            }
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("Fine-tune face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateFaceAdjustment(adjustment)
                        dismiss()
                    }
                }
            }
            .onAppear { adjustment = model.profile.face?.adjustment ?? .identity }
        }
    }

    private func tuned(_ face: FaceAsset) -> FaceAsset {
        var copy = face
        copy.adjustment = adjustment
        return copy
    }

    private func tuneSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(width: 96, alignment: .leading)
            Slider(value: value, in: range).tint(Brand.coral)
        }
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Acknowledgements").font(Brand.display(28))
                Group {
                    Text("Clothing recognition").font(.headline)
                    Text("OutfitSim uses a SegFormer-B2 clothing-parsing model (\"mattmdjaga/segformer_b2_clothes\", fine-tuned on the ATR human-parsing dataset), converted to Core ML. SegFormer is © NVIDIA and licensed for non-commercial use under the NVIDIA Source Code License; the ATR dataset is provided for research. Make sure your use of the app complies with these terms.")
                    Text("Apple frameworks").font(.headline)
                    Text("Face landmarks, body pose, person and subject segmentation are provided by Apple's Vision framework on device.")
                    Text("Proportions").font(.headline)
                    Text("Body proportions follow the Drillis & Contini anthropometric segment ratios, with head size scaled allometrically with height.")
                }
                .font(.subheadline)
            }
            .padding(20)
        }
        .background(Brand.canvas.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
