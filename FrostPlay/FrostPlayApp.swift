import SwiftUI

@main
struct FrostPlayApp: App {
    @StateObject private var store = FrostPlayStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.settings.theme.colorScheme)
        }
    }
}
