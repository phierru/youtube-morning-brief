import Foundation

@MainActor
final class PipelineRunner: ObservableObject {
    @Published var output = ""
    @Published var manualRunActive = false
    /// A run started outside the app (the scheduled LaunchAgent), detected via the lockfile.
    @Published var externalRunActive = false
    @Published var lastOutcome: String?

    var runInProgress: Bool { manualRunActive || externalRunActive }

    private var process: Process?
    private var lockTimer: Timer?

    init() {
        pollLock()
        lockTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollLock() }
        }
        lastOutcome = Self.readLastOutcome()
    }

    func runNow(lookbackHours: Int?) {
        guard !runInProgress else { return }
        output = ""
        manualRunActive = true

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.venvPython.path)
        var args = [Paths.script.path]
        if let h = lookbackHours { args += ["--lookback", String(h)] }
        p.arguments = args
        p.currentDirectoryURL = Paths.projectDir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.output += text }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                self.manualRunActive = false
                self.process = nil
                self.output += "\n[finished, exit code \(proc.terminationStatus)]\n"
                self.lastOutcome = Self.readLastOutcome()
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            manualRunActive = false
            output += "failed to start: \(error.localizedDescription)\n"
        }
    }

    private func pollLock() {
        var locked = false
        if let s = try? String(contentsOf: Paths.lockFile, encoding: .utf8),
           let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            locked = kill(pid, 0) == 0 || errno == EPERM
        }
        // only report as external if it isn't our own child run
        externalRunActive = locked && !manualRunActive
    }

    /// Tail the pipeline log for the most recent per-subject outcome lines.
    static func readLastOutcome() -> String? {
        guard let text = try? String(contentsOf: Paths.logFile, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").suffix(120)
        let outcomes = lines.filter {
            $0.contains("report written:") || $0.contains("no new videos")
        }
        guard !outcomes.isEmpty else { return nil }
        return outcomes.suffix(2).map { line in
            var s = String(line)
            if let r = s.range(of: #"report written: .*/"#, options: .regularExpression) {
                s.replaceSubrange(r, with: "report written: ")
            }
            return s
        }.joined(separator: "\n")
    }
}
