import SwiftUI

struct LogView: View {
    @EnvironmentObject private var runner: PipelineRunner
    @State private var text = ""
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if runner.runInProgress {
                    Label("Run in progress", systemImage: "clock.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label("Idle", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.logFile])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "No log yet." : text)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: text) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear {
                    load()
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .padding()
        .navigationTitle("Log")
        .onReceive(refresh) { _ in load() }
    }

    /// Tail the last ~64 KB of the log — enough for several runs, cheap to re-read.
    private func load() {
        guard let handle = try? FileHandle(forReadingFrom: Paths.logFile) else {
            text = ""
            return
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 65_536 ? size - 65_536 : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              var s = String(data: data, encoding: .utf8) else { return }
        if offset > 0, let nl = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: nl)...])  // drop partial first line
        }
        if s != text { text = s }
    }
}
