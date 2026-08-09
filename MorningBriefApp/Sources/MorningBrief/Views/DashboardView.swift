import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var agent: LaunchAgentManager
    @EnvironmentObject private var runner: PipelineRunner
    @State private var scheduleDate = Date()
    @State private var suppressScheduleSave = false
    @State private var lookbackText = ""
    private let resync = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Schedule") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Daily brief enabled", isOn: Binding(
                        get: { agent.enabled },
                        set: { agent.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)

                    HStack {
                        DatePicker("Run time",
                                   selection: $scheduleDate,
                                   displayedComponents: .hourAndMinute)
                            .frame(maxWidth: 200)
                        Spacer()
                        if let next = agent.nextRunDate {
                            Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Schedule disabled")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let outcome = runner.lastOutcome {
                        Text("Last run:\n\(outcome)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    if let err = agent.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Manual run") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button {
                            runner.runNow(lookbackHours: Int(lookbackText))
                        } label: {
                            Label(runner.runInProgress ? "Running…" : "Run Now",
                                  systemImage: "play.fill")
                        }
                        .disabled(runner.runInProgress)

                        Button(role: .destructive) {
                            runner.stop()
                        } label: {
                            Label(runner.stopping ? "Stopping…" : "Stop",
                                  systemImage: "stop.fill")
                        }
                        .disabled(!runner.runInProgress || runner.stopping)
                        .help("Stop the run in progress. Nothing partial is "
                              + "written; the next run picks up where this left off.")

                        TextField("look back (hours, optional)", text: $lookbackText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)

                        if runner.externalRunActive {
                            Label("Scheduled run in progress", systemImage: "clock")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(runner.output.isEmpty ? "Output appears here." : runner.output)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(minHeight: 180)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: runner.output) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .padding(6)
            }
        }
        .padding()
        .onAppear {
            agent.refresh()
            suppressScheduleSave = true
            scheduleDate = Calendar.current.date(
                bySettingHour: agent.scheduleHour,
                minute: agent.scheduleMinute,
                second: 0, of: Date()) ?? Date()
            DispatchQueue.main.async { suppressScheduleSave = false }
        }
        .onReceive(resync) { _ in
            // keep UI in sync if the agent/plist is changed outside the app
            let wasEnabled = agent.enabled
            let (h, m) = (agent.scheduleHour, agent.scheduleMinute)
            agent.refresh()
            if agent.enabled != wasEnabled
                || agent.scheduleHour != h || agent.scheduleMinute != m {
                suppressScheduleSave = true
                scheduleDate = Calendar.current.date(
                    bySettingHour: agent.scheduleHour,
                    minute: agent.scheduleMinute,
                    second: 0, of: Date()) ?? Date()
                DispatchQueue.main.async { suppressScheduleSave = false }
            }
        }
        .onChange(of: scheduleDate) {
            guard !suppressScheduleSave else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: scheduleDate)
            agent.setSchedule(hour: c.hour ?? 7, minute: c.minute ?? 0)
        }
    }
}
