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

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> Result {
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
        p.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(status: p.terminationStatus, stdout: o, stderr: e)
    }
}
