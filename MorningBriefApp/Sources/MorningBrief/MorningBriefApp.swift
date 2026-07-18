import SwiftUI

@main
struct MorningBriefApp: App {
    var body: some Scene {
        Window("Morning Brief", id: "main") {
            ContentView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 720, height: 480)

        MenuBarExtra("Morning Brief", systemImage: "sunrise.fill") {
            MenuBarView()
        }
    }
}
