import OutfitKit
import SwiftUI

@main
struct OutfitSimApp: App {
    @StateObject private var model = AppModel.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Brand.coral)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.profile.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ClosetView()
                .tabItem { Label("Closet", systemImage: "hanger") }
                .tag(AppTab.closet)
            StudioView()
                .tabItem { Label("Studio", systemImage: "figure.stand") }
                .tag(AppTab.studio)
            OutfitsView()
                .tabItem { Label("Outfits", systemImage: "square.grid.2x2") }
                .tag(AppTab.outfits)
            ProfileView()
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(AppTab.me)
        }
    }
}
