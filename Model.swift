import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Darwin

// MARK: - Model

struct Item: Identifiable {
    enum Kind { case app, window }
    let id: String
    let kind: Kind
    let pid: pid_t
    let title: String
    let subtitle: String
    let icon: NSImage?
    let memoryMB: Double
    let window: AXUIElement?
}

final class Model: ObservableObject {
    enum Mode { case apps, windows }

    @Published var mode: Mode = .apps
    @Published var items: [Item] = []
    @Published var selection = 0
    @Published var filter = "" { didSet { selection = 0 } }
    @Published var status = ""
    @Published var loading = false

    private var generation = 0
    private var confirmCloseAll = false

    var visible: [Item] {
        guard !filter.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(filter) ||
            $0.subtitle.localizedCaseInsensitiveContains(filter)
        }
    }

    var selectedItem: Item? {
        let v = visible
        return v.indices.contains(selection) ? v[selection] : nil
    }

    // MARK: Laden

    func reload(keepSelection: Bool = false) {
        generation += 1
        let gen = generation
        let mode = self.mode
        let previousID = selectedItem?.id
        loading = true

        if mode == .windows && !Self.axTrusted(prompt: false) {
            items = []
            loading = false
            needsPermission = true
            startPermissionPolling()
            return
        }
        needsPermission = false

        DispatchQueue.global(qos: .userInitiated).async {
            var unresponsive = 0
            let result = mode == .apps ? Self.loadApps() : Self.loadWindows(unresponsive: &unresponsive)
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.items = result
                self.loading = false
                if mode == .windows && unresponsive > 0 && self.status.isEmpty {
                    self.status = "\(unresponsive) app(s) gaven geen antwoord (te traag of geen vensters)."
                }
                if keepSelection, let id = previousID, let idx = self.visible.firstIndex(where: { $0.id == id }) {
                    self.selection = idx
                } else {
                    self.clampSelection()
                }
            }
        }
    }

    private static func regularApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }
    }

    private static func loadApps() -> [Item] {
        let tree = ProcTree()
        return regularApps()
            .filter { $0.bundleIdentifier != "com.apple.finder" }
            .map { app in
                Item(id: "app-\(app.processIdentifier)", kind: .app, pid: app.processIdentifier,
                     title: app.localizedName ?? "Onbekend",
                     subtitle: app.isHidden ? "verborgen" : "",
                     icon: app.icon, memoryMB: tree.totalMB(app.processIdentifier), window: nil)
            }
            .sorted { $0.memoryMB > $1.memoryMB }
    }

    private static func loadWindows(unresponsive: inout Int) -> [Item] {
        var out: [Item] = []
        for app in regularApps() {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 1.0) // trage apps niet eindeloos laten blokkeren
            var value: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &value)
            guard err == .success, let windows = value as? [AXUIElement] else {
                if err == .cannotComplete { unresponsive += 1 }
                continue
            }
            let appName = app.localizedName ?? "Onbekend"
            for (i, w) in windows.enumerated() {
                if let sub = axString(w, kAXSubroleAttribute), sub != (kAXStandardWindowSubrole as String) { continue }
                let title = axString(w, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? "(zonder titel)"
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized)
                let isMin = (minimized as? Bool) ?? false
                out.append(Item(id: "win-\(app.processIdentifier)-\(i)-\(title)", kind: .window,
                                pid: app.processIdentifier, title: title,
                                subtitle: appName + (isMin ? " · geminimaliseerd" : ""),
                                icon: app.icon, memoryMB: 0, window: w))
            }
        }
        return out
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    static func axTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    // MARK: Toestemming

    @Published var needsPermission = false
    private var permissionTimer: Timer?

    /// Opent Systeeminstellingen op de juiste plek en zet Sluiter in de lijst.
    func requestPermission() {
        _ = Self.axTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Controleert elke seconde of de toestemming er is, en laadt dan automatisch.
    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if Self.axTrusted(prompt: false) {
                t.invalidate()
                self.permissionTimer = nil
                self.needsPermission = false
                if self.mode == .windows {
                    self.status = "Toegang gekregen ✓"
                    self.reload()
                }
            }
        }
    }

    // MARK: Acties

    func move(_ delta: Int) {
        let count = visible.count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
        confirmCloseAll = false
    }

    func jump(toEnd: Bool) {
        selection = toEnd ? max(0, visible.count - 1) : 0
    }

    func toggleMode() {
        mode = (mode == .apps) ? .windows : .apps
        filter = ""
        status = ""
        items = []
        reload()
    }

    func closeSelected(force: Bool) {
        guard let item = selectedItem else { return }
        confirmCloseAll = false
        close(item, force: force)
        items.removeAll { $0.id == item.id }
        clampSelection()
        scheduleResync()
    }

    func closeAllVisible() {
        let targets = visible
        guard !targets.isEmpty else { return }
        if !confirmCloseAll {
            confirmCloseAll = true
            status = "Druk nogmaals ⌘⏎ om alle \(targets.count) \(mode == .apps ? "apps" : "vensters") te sluiten."
            return
        }
        confirmCloseAll = false
        targets.forEach { close($0, force: false) }
        let ids = Set(targets.map(\.id))
        items.removeAll { ids.contains($0.id) }
        filter = ""
        status = "\(targets.count) gesloten."
        scheduleResync()
    }

    private func close(_ item: Item, force: Bool) {
        switch item.kind {
        case .app:
            guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
            let ok = force ? app.forceTerminate() : app.terminate()
            status = ok ? "\(item.title) \(force ? "geforceerd gestopt" : "wordt afgesloten")…"
                        : "\(item.title) reageert niet — probeer ⇧⏎ om te forceren."
        case .window:
            guard let w = item.window else { return }
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &button) == .success,
               let b = button, CFGetTypeID(b) == AXUIElementGetTypeID() {
                AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
                status = "Venster “\(item.title)” gesloten."
            } else {
                status = "Dit venster heeft geen sluitknop."
            }
        }
    }

    private func clampSelection() {
        selection = min(selection, max(0, visible.count - 1))
    }

    /// Na een sluit-actie de lijst opnieuw ophalen (bv. als een app weigerde te stoppen).
    private func scheduleResync() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, AppDelegate.shared?.window.isVisible == true else { return }
            self.reload(keepSelection: true)
        }
    }
}

