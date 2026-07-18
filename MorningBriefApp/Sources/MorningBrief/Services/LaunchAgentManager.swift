import Foundation

@MainActor
final class LaunchAgentManager: ObservableObject {
    @Published var enabled = false
    @Published var scheduleHour = 7
    @Published var scheduleMinute = 0
    @Published var lastError: String?

    private var domain: String { "gui/\(getuid())" }
    private var serviceTarget: String { "\(domain)/\(Paths.agentLabel)" }

    func refresh() {
        enabled = Shell.run("/bin/launchctl", ["print", serviceTarget]).status == 0
        if let (h, m) = readScheduleFromPlist() {
            scheduleHour = h
            scheduleMinute = m
        }
    }

    func setEnabled(_ on: Bool) {
        lastError = nil
        let r = on
            ? Shell.run("/bin/launchctl", ["bootstrap", domain, Paths.agentPlist.path])
            : Shell.run("/bin/launchctl", ["bootout", serviceTarget])
        if r.status != 0 {
            lastError = "launchctl failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)"
        }
        refresh()
    }

    func setSchedule(hour: Int, minute: Int) {
        lastError = nil
        do {
            let data = try Data(contentsOf: Paths.agentPlist)
            var plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] ?? [:]
            plist["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
            let newData = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try newData.write(to: Paths.agentPlist, options: .atomic)
        } catch {
            lastError = "cannot update plist: \(error.localizedDescription)"
            return
        }
        scheduleHour = hour
        scheduleMinute = minute
        if enabled {  // reload so launchd picks up the new time
            Shell.run("/bin/launchctl", ["bootout", serviceTarget])
            let r = Shell.run("/bin/launchctl", ["bootstrap", domain, Paths.agentPlist.path])
            if r.status != 0 {
                lastError = "reload failed: \(r.stderr)"
            }
            refresh()
        }
    }

    var nextRunDate: Date? {
        guard enabled else { return nil }
        var comps = DateComponents()
        comps.hour = scheduleHour
        comps.minute = scheduleMinute
        return Calendar.current.nextDate(
            after: Date(), matching: comps, matchingPolicy: .nextTime)
    }

    private func readScheduleFromPlist() -> (Int, Int)? {
        guard let data = try? Data(contentsOf: Paths.agentPlist),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let cal = plist["StartCalendarInterval"] as? [String: Any],
              let h = cal["Hour"] as? Int
        else { return nil }
        return (h, cal["Minute"] as? Int ?? 0)
    }
}
