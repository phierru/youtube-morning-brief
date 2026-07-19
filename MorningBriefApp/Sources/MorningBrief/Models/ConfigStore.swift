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

    init() { load() }

    func load() {
        do {
            let data = try Data(contentsOf: Paths.configFile)
            raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            subjects = (raw["subjects"] as? [[String: Any]] ?? []).map { s in
                BriefSubject(
                    name: s["name"] as? String ?? "?",
                    channels: (s["channels"] as? [[String: Any]] ?? []).map {
                        BriefChannel(name: $0["name"] as? String ?? "?",
                                     channelId: $0["id"] as? String ?? "")
                    })
            }
        } catch {
            lastError = "cannot read config.json: \(error.localizedDescription)"
        }
    }

    private func save() {
        raw["subjects"] = subjects.map { s in
            ["name": s.name,
             "channels": s.channels.map { ["name": $0.name, "id": $0.channelId] }]
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Paths.configFile, options: .atomic)
            lastError = nil
        } catch {
            lastError = "cannot write config.json: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addSubject(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !subjects.contains(where: { $0.name == trimmed }) else {
            lastError = "subject name is empty or already exists"
            return false
        }
        subjects.append(BriefSubject(name: trimmed, channels: []))
        save()
        return true
    }

    func removeSubject(id subjectID: String) {
        subjects.removeAll { $0.id == subjectID }
        save()
    }

    @discardableResult
    func addChannel(_ channel: BriefChannel, toSubject subjectID: String) -> Bool {
        guard let i = subjects.firstIndex(where: { $0.id == subjectID }) else { return false }
        guard !subjects[i].channels.contains(where: { $0.channelId == channel.channelId }) else {
            return false  // duplicate
        }
        subjects[i].channels.append(channel)
        save()
        return true
    }

    func removeChannel(id channelId: String, fromSubject subjectID: String) {
        guard let i = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[i].channels.removeAll { $0.channelId == channelId }
        save()
    }
}
