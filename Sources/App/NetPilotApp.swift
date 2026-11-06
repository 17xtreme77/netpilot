import SwiftUI

@main
struct NetPilotApp: App {
    @StateObject private var usage = UsageStore()
    @StateObject private var proxy = ProxyManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(usage)
                .environmentObject(proxy)
                .preferredColorScheme(nil)
        }
    }
}
