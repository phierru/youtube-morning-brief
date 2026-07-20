import Foundation

struct BriefChannel: Identifiable, Hashable {
    var name: String
    var channelId: String
    var id: String { channelId }
}

struct BriefSubject: Identifiable, Hashable {
    var name: String
    var channels: [BriefChannel]
    var id: String { name }
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var subjects: [BriefSubject] = []
    @Published var lastError: String?

    /// Raw config.json contents — kept as a dictionary so keys this app
    /// doesn't know about survive a round-trip untouched.
    private var raw: [String: Any] = [:]
    /// Saves are refused while false, so a bad load can never be
    /// silently overwritten with an empty config.
    private var configValid = false

    init() { load() }

    func load() {
        configValid = false
        do {
            let data = try Data(contentsOf: Paths.configFile)
            guard let parsed = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                lastError = "config.json is not a JSON object — fix it manually"
                return
            }
            if let s = parsed["subjects"], !(s is [[String: Any]]) {
                lastError = "config.json: \"subjects\" has an unexpected shape — fix it manually"
                return
            }
            raw = parsed
            subjects = (raw["subjects"] as? [[String: Any]] ?? []).map { s in
                BriefSubject(
                    name: s["name"] as? String ?? "?",
                    channels: (s["channels"] as? [[String: Any]] ?? []).map {
                        BriefChannel(name: $0["name"] as? String ?? "?",
                                     channelId: $0["id"] as? String ?? "")
                    })
            }
            configValid = true
            lastError = nil
        } catch {
            lastError = "cannot read config.json: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard configValid else {
            lastError = "not saving: config.json didn't load correctly"
            return false
        }
        raw["subjects"] = subjects.map { s in
            ["name": s.name,
             "channels": s.channels.map { ["name": $0.name, "id": $0.channelId] }]
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Paths.configFile, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = "cannot write config.json: \(error.localizedDescription)"
            return false
        }
    }

    /// Mutate subjects, save; roll back the mutation if the save fails.
    private func mutating(_ change: (inout [BriefSubject]) -> Void) -> Bool {
        let snapshot = subjects
        change(&subjects)
        if save() { return true }
        subjects = snapshot
        return false
    }

    static func validateSubjectName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Subject name must not be empty." }
        if trimmed.hasPrefix(".") { return "Subject name must not start with a dot." }
        if trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:\n\r\t")) != nil {
            return "Subject name must not contain /, \\, : or line breaks."
        }
        return nil
    }

    @discardableResult
    func addSubject(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let problem = Self.validateSubjectName(trimmed) {
            lastError = problem
            return false
        }
        guard !subjects.contains(where: { $0.name == trimmed }) else {
            lastError = "A subject with this name already exists."
            return false
        }
        return mutating { $0.append(BriefSubject(name: trimmed, channels: [])) }
    }

    @discardableResult
    func removeSubject(id subjectID: String) -> Bool {
        mutating { $0.removeAll { $0.id == subjectID } }
    }

    @discardableResult
    func addChannel(_ channel: BriefChannel, toSubject subjectID: String) -> Bool {
        guard let i = subjects.firstIndex(where: { $0.id == subjectID }) else { return false }
        guard !subjects[i].channels.contains(where: { $0.channelId == channel.channelId }) else {
            lastError = nil  // duplicate is not a persistence error
            return false
        }
        return mutating { $0[i].channels.append(channel) }
    }

    @discardableResult
    func removeChannel(id channelId: String, fromSubject subjectID: String) -> Bool {
        guard let i = subjects.firstIndex(where: { $0.id == subjectID }) else { return false }
        return mutating { $0[i].channels.removeAll { $0.channelId == channelId } }
    }

    func readSettings() -> PipelineSettings {
        PipelineSettings(
            lookbackHours: raw["lookback_hours"] as? Int ?? 48,
            minDurationSeconds: raw["min_duration_seconds"] as? Int ?? 120,
            transcriptDeferHours: raw["transcript_defer_hours"] as? Int ?? 24,
            maxTranscriptChars: raw["max_transcript_chars"] as? Int ?? 60000,
            claudeModel: raw["claude_model"] as? String ?? "sonnet")
    }

    @discardableResult
    func saveSettings(_ s: PipelineSettings) -> Bool {
        raw["lookback_hours"] = s.lookbackHours
        raw["min_duration_seconds"] = s.minDurationSeconds
        raw["transcript_defer_hours"] = s.transcriptDeferHours
        raw["max_transcript_chars"] = s.maxTranscriptChars
        raw["claude_model"] = s.claudeModel
        return save()
    }
}
