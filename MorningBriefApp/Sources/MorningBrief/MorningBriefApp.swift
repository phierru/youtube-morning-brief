import SwiftUI

@main
struct MorningBriefApp: App {
    @StateObject private var agent = LaunchAgentManager()
    @StateObject private var runner = PipelineRunner()

    var body: some Scene {
        Window("Morning Brief", id: "main") {
            ContentView()
                .frame(minWidth: 640, minHeight: 480)
                .environmentObject(agent)
                .environmentObject(runner)
        }
        .defaultSize(width: 720, height: 560)

        MenuBarExtra("Morning Brief", systemImage: "sunrise.fill") {
            MenuBarView()
                .environmentObject(agent)
                .environmentObject(runner)
        }
    }
}
