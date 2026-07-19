import SwiftUI

@main
struct MorningBriefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
                .background(MenuBarBridge(delegate: delegate,
                                          agent: agent, runner: runner))
        }
        .defaultSize(width: 860, height: 560)
    }
}

/// Invisible helper that hands the SwiftUI openWindow action and the shared
/// state objects to the AppKit delegate exactly once.
private struct MenuBarBridge: View {
    let delegate: AppDelegate
    let agent: LaunchAgentManager
    let runner: PipelineRunner
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                delegate.attach(agent: agent, runner: runner) {
                    openWindow(id: "main")
                }
            }
    }
}
