import AppKit
import Combine

/// Owns the menu bar status item. Managed manually (rather than via
/// MenuBarExtra) so the icon and menu update reliably with app state.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private var agent: LaunchAgentManager?
    private var runner: PipelineRunner?
    private var openMain: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sunrise.fill",
                                     accessibilityDescription: "Morning Brief")
        statusItem = item
        refreshUI()
    }

    /// Called once from the SwiftUI layer to wire up shared state and the
    /// openWindow action (captured from an active scene, usable any time).
    func attach(agent: LaunchAgentManager, runner: PipelineRunner,
                openMain: @escaping () -> Void) {
        guard self.agent == nil else { return }
        self.agent = agent
        self.runner = runner
        self.openMain = openMain

        agent.objectWillChange.merge(with: runner.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshUI() }
            }
            .store(in: &cancellables)
        refreshUI()
    }

    private func refreshUI() {
        let symbol: String
        if runner?.runInProgress == true {
            symbol = "arrow.triangle.2.circlepath"
        } else if agent?.enabled == true {
            symbol = "sunrise.fill"
        } else {
            symbol = "sunrise"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbol,
                                            accessibilityDescription: "Morning Brief")
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let status: String
        if runner?.runInProgress == true {
            status = "Run in progress…"
        } else if let next = agent?.nextRunDate {
            status = "Next run: \(next.formatted(date: .abbreviated, time: .shortened))"
        } else {
            status = "Schedule disabled"
        }
        menu.addItem(disabledItem(status))

        if let outcome = runner?.lastOutcome,
           let line = outcome.split(separator: "\n").last {
            let short = String(line).replacingOccurrences(
                of: #"^\[[^\]]+\] "#, with: "", options: .regularExpression)
            menu.addItem(disabledItem(String(short.prefix(70))))
        }
        menu.addItem(.separator())

        let run = NSMenuItem(title: "Run Now", action: #selector(runNow), keyEquivalent: "")
        run.target = self
        run.isEnabled = runner?.runInProgress != true
        menu.addItem(run)

        let open = NSMenuItem(title: "Open Morning Brief",
                              action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func runNow() { runner?.runNow(lookbackHours: nil) }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openMain?()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
