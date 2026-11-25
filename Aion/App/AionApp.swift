import SwiftUI

@main
struct AionApp: App {
    @State private var store = AionStore()

    var body: some Scene {
        WindowGroup {
            MainTabContainerView(store: store)
                .tint(AionTheme.terracotta)
                .preferredColorScheme(store.appearanceMode.colorScheme)
        }
    }
}
