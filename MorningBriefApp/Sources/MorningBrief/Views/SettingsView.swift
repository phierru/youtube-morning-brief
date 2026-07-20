import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var config: ConfigStore
    @State private var settings = PipelineSettings(
        lookbackHours: 48, minDurationSeconds: 120, transcriptDeferHours: 24,
        maxTranscriptChars: 60000, claudeModel: "sonnet")
    @State private var saved = false

    private var stored: PipelineSettings { config.readSettings() }
    private var dirty: Bool { settings != stored }

    var body: some View {
        Form {
            Section("Pipeline") {
                TextField("Lookback (hours)", value: $settings.lookbackHours,
                          format: .number)
                Text("How far back each run searches for new videos.")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Minimum video duration (seconds)",
                          value: $settings.minDurationSeconds, format: .number)
                Text("Videos shorter than this are skipped (filters out Shorts).")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Transcript defer window (hours)",
                          value: $settings.transcriptDeferHours, format: .number)
                Text("How long to wait for captions before summarizing from the description.")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Max transcript characters",
                          value: $settings.maxTranscriptChars, format: .number)
                Text("Transcripts are truncated to this length before summarization.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude") {
                TextField("Model", text: $settings.claudeModel)
                Text("Passed to `claude -p --model …` (e.g. sonnet, opus, haiku).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Save") {
                        if config.saveSettings(settings) {
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saved = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!dirty || settings.validationError != nil)

                    Button("Revert") { settings = stored }
                        .disabled(!dirty)

                    if saved {
                        Label("Saved — takes effect on the next run",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let err = settings.validationError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                if let err = config.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { settings = stored }
    }
}
