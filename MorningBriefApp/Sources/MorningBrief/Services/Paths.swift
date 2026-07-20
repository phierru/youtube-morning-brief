import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Pipeline checkout location. Defaults to ~/Projects/YouTubeMorningBrief;
    /// override with: defaults write com.francescolardieri.morningbrief projectDir /path/to/checkout
    static let projectDir: URL = {
        if let custom = UserDefaults.standard.string(forKey: "projectDir") {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent("Projects/YouTubeMorningBrief")
    }()

    static let venvPython = projectDir.appendingPathComponent(".venv/bin/python")
    static let script = projectDir.appendingPathComponent("morning_brief.py")
    static let configFile = projectDir.appendingPathComponent("config.json")
    static let logFile = projectDir.appendingPathComponent("logs/brief.log")
    static let lockFile = projectDir.appendingPathComponent("run.lock")

    static let agentLabel = "com.morningbrief.daily"
    static let agentPlist = home.appendingPathComponent(
        "Library/LaunchAgents/\(agentLabel).plist")
}

enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs a process, draining stdout/stderr concurrently (a pipe left
    /// undrained until exit can deadlock on >64KB of output) and terminating
    /// the child if it exceeds the timeout.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String],
                    timeout: TimeInterval = 20) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }

        var outData = Data(), errData = Data()
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global().async {
            outData = out.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        drain.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }

        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            p.waitUntilExit()
            exited.signal()
        }
        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            _ = exited.wait(timeout: .now() + 3)
        }
        drain.wait()

        return Result(
            status: timedOut ? -1 : p.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: timedOut ? "timed out after \(Int(timeout))s"
                             : (String(data: errData, encoding: .utf8) ?? ""))
    }
}
