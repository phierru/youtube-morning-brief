import SwiftUI

@main
struct MorningBriefApp: App {
    @StateObject private var agent = LaunchAgentManager()
    @StateObject private var runner = PipelineRunner()
    @StateObject private var config = ConfigStore()

    var body: some Scene {
        Window("Morning Brief", id: "main") {
            ContentView()
                .frame(minWidth: 780, minHeight: 500)
                .environmentObject(agent)
                .environmentObject(runner)
                .environmentObject(config)
        }
        .defaultSize(width: 720, height: 560)

        MenuBarExtra("Morning Brief", systemImage: "sunrise.fill") {
            MenuBarView()
                .environmentObject(agent)
                .environmentObject(runner)
        }
    }
}
