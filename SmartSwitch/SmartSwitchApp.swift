import SwiftUI

@main
struct SmartSwitchApp: App {
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
