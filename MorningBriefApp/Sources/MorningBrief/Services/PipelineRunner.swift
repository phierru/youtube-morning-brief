import Foundation

@MainActor
final class PipelineRunner: ObservableObject {
    @Published var output = ""
    @Published var manualRunActive = false
    /// A run started outside the app (the scheduled LaunchAgent), detected via the lockfile.
    @Published var externalRunActive = false
    @Published var lastOutcome: String?
    /// Set between a stop request and the run actually going away, so the
    /// button can show that the signal was delivered but the child is still
    /// unwinding (it has to finish killing its own claude/yt-dlp child).
    @Published var stopping = false

    var runInProgress: Bool { manualRunActive || externalRunActive }

    private var process: Process?
    private var lockTimer: Timer?
    /// Append handle on the shared pipeline log. The scheduled LaunchAgent gets
    /// its output there via StandardOutPath; manual runs have to tee it
    /// themselves, or they leave no record once the window closes.
    private var logHandle: FileHandle?

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
        logHandle = Self.openLogForAppending()
        writeLog("\n[manual run started \(Self.stamp())]\n")

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
            Task { @MainActor in
                self?.output += text
                self?.logHandle?.write(data)
            }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            // whatever landed in the pipe between the last handler call and exit
            let remaining = pipe.fileHandleForReading.availableData
            Task { @MainActor in
                guard let self else { return }
                if !remaining.isEmpty {
                    self.output += String(data: remaining, encoding: .utf8) ?? ""
                    self.logHandle?.write(remaining)
                }
                self.manualRunActive = false
                self.stopping = false
                self.process = nil
                let tail = "\n[finished, exit code \(proc.terminationStatus)]\n"
                self.output += tail
                self.writeLog(tail)
                self.logHandle?.closeFile()
                self.logHandle = nil
                self.lastOutcome = Self.readLastOutcome()
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            manualRunActive = false
            let msg = "failed to start: \(error.localizedDescription)\n"
            output += msg
            writeLog(msg)
            logHandle?.closeFile()
            logHandle = nil
        }
    }

    /// Ask the current run to stop. Works for our own child and for a run
    /// started outside the app (the LaunchAgent), which we can only reach
    /// through the PID in the lockfile. SIGTERM lets the pipeline unwind
    /// cleanly — it kills its in-flight child and releases the lock — so we
    /// only escalate to SIGKILL if it hasn't gone away.
    func stop() {
        guard runInProgress, !stopping else { return }
        stopping = true
        let note = "\n[stop requested \(Self.stamp())]\n"
        output += note
        writeLog(note)

        if manualRunActive, let p = process {
            let pid = p.processIdentifier
            p.terminate()
            escalate(pid: pid)
        } else if externalRunActive, let pid = Self.lockfilePID() {
            kill(pid, SIGTERM)
            escalate(pid: pid)
        }
    }

    /// SIGKILL anything still alive well after the SIGTERM. The pipeline's own
    /// claude call can take up to 600s, but the signal handler kills it rather
    /// than waiting on it, so 15s is generous.
    private func escalate(pid: pid_t) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.stopping else { return }
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    private static func lockfilePID() -> pid_t? {
        guard let s = try? String(contentsOf: Paths.lockFile, encoding: .utf8) else { return nil }
        return pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func writeLog(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        logHandle?.write(data)
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    /// Open the pipeline log for appending, creating it (and logs/) if needed.
    private static func openLogForAppending() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.logFile.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Paths.logFile.path) {
            fm.createFile(atPath: Paths.logFile.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: Paths.logFile) else { return nil }
        h.seekToEndOfFile()
        return h
    }

    private func pollLock() {
        var locked = false
        if let s = try? String(contentsOf: Paths.lockFile, encoding: .utf8),
           let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            locked = kill(pid, 0) == 0 || errno == EPERM
        }
        // only report as external if it isn't our own child run
        externalRunActive = locked && !manualRunActive
        // an external run we signalled has now gone away
        if !runInProgress { stopping = false }
    }

    /// Tail the pipeline log for the most recent per-subject outcome lines.
    static func readLastOutcome() -> String? {
        guard let text = try? String(contentsOf: Paths.logFile, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").suffix(120)
        let outcomes = lines.filter {
            $0.contains("report written:") || $0.contains("no new videos")
                || $0.contains("FATAL")
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
