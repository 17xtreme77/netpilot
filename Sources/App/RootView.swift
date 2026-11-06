import SwiftUI

struct RootView: View {
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("概览", systemImage: "chart.bar.fill") }

            HotspotView()
                .tabItem { Label("热点", systemImage: "personalhotspot") }

            ProxyView()
                .tabItem { Label("代理", systemImage: "shield.lefthalf.filled") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.mint)
        .preferredColorScheme(.dark)
        .toolbarBackground(Theme.bar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear { usage.startSampling(interval: 1.0) }
        .onDisappear { usage.stopSampling() }
    }
}
