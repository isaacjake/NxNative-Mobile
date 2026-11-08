import SwiftUI

@main
struct NxNativeMobileApp: App {
    init() {
        AppLog.add("App launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
