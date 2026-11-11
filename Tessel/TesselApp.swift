import SwiftUI

@main
struct TesselApp: App {
    @State private var store = FrameStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
        }
    }
}
