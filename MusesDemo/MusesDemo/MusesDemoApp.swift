import SwiftUI

@main
struct MusesDemoApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
        }
    }
}
