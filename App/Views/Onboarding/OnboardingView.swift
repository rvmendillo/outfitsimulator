import OutfitKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var body_ = BodyProfile()
    @State private var units: UnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            switch step {
            case 0: welcome
            case 1: howItWorks
            case 2: proportions
            default:
                FaceSetupView(showsSkip: true) {
                    model.completeOnboarding()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear { body_ = model.profile.body }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            AppIconTile(size: 120)
            Wordmark(size: 44)
            Text(Brand.tagline)
                .font(Brand.display(22, weight: .regular))
                .foregroundStyle(Brand.secondaryInk)
            Spacer()
            Button("Get started") { step = 1 }
                .buttonStyle(.brandPrimary)
                .accessibilityIdentifier("onboarding.start")
            Text("Private by design — photos never leave your iPhone.")
                .font(.footnote)
                .foregroundStyle(Brand.secondaryInk)
        }
        .padding(28)
        .transition(.opacity)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("How it works").font(Brand.display(34)).foregroundStyle(Brand.ink).padding(.top, 40)
            feature("camera.viewfinder", "Snap your clothes",
                    "Photograph an outfit you're wearing or pieces laid flat. Every piece is cut out automatically.")
            feature("square.stack.3d.up", "Mix & match",
                    "Combine tops, bottoms, shoes and accessories into as many outfits as you like — or let us suggest some.")
            feature("person.crop.square", "See it on you",
                    "Add a selfie. Your face is scaled to your height so clothes sit where they would in real life.")
            Spacer()
            Button("Continue") { step = 2 }
                .buttonStyle(.brandPrimary)
                .accessibilityIdentifier("onboarding.continue")
        }
        .padding(28)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.gradient))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Brand.ink)
                Text(text).font(.subheadline).foregroundStyle(Brand.secondaryInk)
            }
        }
    }

    private var proportions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your proportions").font(Brand.display(32)).foregroundStyle(Brand.ink).padding(.top, 24)
                Text("Your height sets how many \"heads tall\" your avatar is, so clothes and face line up realistically.")
                    .font(.subheadline).foregroundStyle(Brand.secondaryInk)
                Picker("Units", selection: $units) {
                    Text("cm").tag(UnitSystem.metric)
                    Text("ft / in").tag(UnitSystem.imperial)
                }
                .pickerStyle(.segmented)
                BodySettingsEditor(body: $body_, units: units)
                Button("Continue") {
                    model.updateBody(body_)
                    model.setUnits(units)
                    step = 3
                }
                .buttonStyle(.brandPrimary)
                .accessibilityIdentifier("onboarding.saveBody")
            }
            .padding(24)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
