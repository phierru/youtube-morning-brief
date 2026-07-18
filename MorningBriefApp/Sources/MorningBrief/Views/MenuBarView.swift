import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var agent: LaunchAgentManager
    @EnvironmentObject private var runner: PipelineRunner

    var body: some View {
        if runner.runInProgress {
            Text("Run in progress…")
        } else if let next = agent.nextRunDate {
            Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
        } else {
            Text("Schedule disabled")
        }
        Divider()
        Button("Run Now") {
            runner.runNow(lookbackHours: nil)
        }
        .disabled(runner.runInProgress)
        Button("Open Morning Brief") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
