import AppKit
import Combine

// MARK: - Werksets: een opgeslagen set apps, later met één klik terug te zetten

struct Workspace: Codable, Identifiable, Equatable {
    struct SavedApp: Codable, Equatable {
        let bundleID: String
        let name: String
    }
    var id = UUID()
    var name: String
    var apps: [SavedApp]
}

final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()
    private let key = "workspaces"

    @Published private(set) var workspaces: [Workspace] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(workspaces) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = list
        }
    }

    private static func currentApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
                && $0.bundleIdentifier != nil && $0.bundleIdentifier != "com.apple.finder"
        }
    }

    // MARK: Opslaan / verwijderen

    /// Vraagt een naam en bewaart de apps die nu open staan.
    func saveCurrent() -> String {
        let apps = Self.currentApps()
        guard !apps.isEmpty else { return "Er staan geen apps open om op te slaan." }
        let alert = NSAlert()
        alert.messageText = "Werkset opslaan"
        alert.informativeText = "Bewaar de \(apps.count) apps die nu open staan:\n"
            + apps.compactMap(\.localizedName).sorted().joined(separator: ", ")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Naam, bv. Werk"
        alert.accessoryView = field
        alert.addButton(withTitle: "Opslaan")
        alert.addButton(withTitle: "Annuleer")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return "" }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? "Werkset \(workspaces.count + 1)" : name
        let saved = apps.map { Workspace.SavedApp(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!) }
        if let i = workspaces.firstIndex(where: { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }) {
            workspaces[i].apps = saved   // zelfde naam = bijwerken
        } else {
            workspaces.append(Workspace(name: finalName, apps: saved))
        }
        return "Werkset “\(finalName)” opgeslagen (\(saved.count) apps)."
    }

    func delete(_ ws: Workspace) {
        workspaces.removeAll { $0.id == ws.id }
    }

    // MARK: Openen / overschakelen

    /// Opent alle apps uit de werkset die nog niet draaien.
    @discardableResult
    func open(_ ws: Workspace) -> String {
        let running = Set(Self.currentApps().compactMap(\.bundleIdentifier))
        var opened = 0, missing: [String] = []
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        for app in ws.apps where !running.contains(app.bundleID) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                opened += 1
            } else {
                missing.append(app.name)
            }
        }
        var msg = opened == 0 ? "Alle apps van “\(ws.name)” staan al open." : "“\(ws.name)”: \(opened) apps worden geopend."
        if !missing.isEmpty { msg += " Niet gevonden: \(missing.joined(separator: ", "))." }
        return msg
    }

    /// Opent de werkset én sluit alle andere apps (behalve beschermde). Vraagt eerst bevestiging.
    func switchTo(_ ws: Workspace) -> String {
        let keep = Set(ws.apps.map(\.bundleID))
        let settings = Settings.shared
        let toClose = Self.currentApps().filter {
            !keep.contains($0.bundleIdentifier!) && !settings.isProtected($0.bundleIdentifier)
        }
        if !toClose.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Overschakelen naar “\(ws.name)”?"
            alert.informativeText = "Deze \(toClose.count) apps worden gesloten:\n"
                + toClose.compactMap(\.localizedName).sorted().joined(separator: ", ")
                + "\n\nApps met niet-bewaard werk vragen zelf of je wilt opslaan."
            alert.addButton(withTitle: "Overschakelen")
            alert.addButton(withTitle: "Annuleer")
            guard alert.runModal() == .alertFirstButtonReturn else { return "" }
            toClose.forEach { _ = $0.terminate() }
        }
        let opened = open(ws)
        return toClose.isEmpty ? opened : "\(toClose.count) apps gesloten. " + opened
    }
}
