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
    let bundleID: String?
    let title: String
    let subtitle: String
    let icon: NSImage?
    var memoryMB: Double
    let window: AXUIElement?
    var cpuPercent: Double? = nil
    var notResponding = false
    var lastUsed: Date? = nil
}

final class Model: ObservableObject {
    enum Mode { case apps, windows }

    enum SortOrder: String, CaseIterable {
        case memory = "Geheugen", cpu = "CPU", idle = "Langst ongebruikt", name = "Naam"
        var next: SortOrder {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    @Published var sortOrder: SortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .memory {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder")
            sortItems()
            selection = 0
        }
    }

    @Published var mode: Mode = .apps
    @Published var items: [Item] = []
    @Published var selection = 0
    @Published var filter = "" { didSet { selection = 0 } }
    @Published var status = ""
    @Published var loading = false
    /// Gemarkeerde items (id's) voor meervoudig sluiten.
    @Published var marked: Set<String> = []
    /// Systeembrede cijfers voor de balk bovenin.
    @Published var stats: SystemStats?

    private var generation = 0
    private var cpuSamples: [pid_t: (ns: UInt64, at: UInt64)] = [:]
    private var hangStrikes: [pid_t: Int] = [:]
    private var liveTimer: Timer?
    private var measuring = false

    init() {
        // Live CPU/geheugen bijwerken zolang het venster in beeld is.
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshStats()
            self?.refreshMetrics()
        }
        refreshStats()
    }

    private func refreshStats() {
        guard stats == nil || (NSApp.isActive && AppDelegate.shared?.window.isVisible == true) else { return }
        let previous = stats
        DispatchQueue.global(qos: .utility).async {
            let s = SystemStats.measure(previous: previous)
            DispatchQueue.main.async { self.stats = s }
        }
    }
    /// Welke bevestiging openstaat (tweede keer drukken = uitvoeren).
    private var pendingConfirm: String?

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
            let metrics = mode == .apps ? Metrics.measure(pids: result.map(\.pid), checkHang: false) : nil
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.items = result
                if let metrics { self.apply(metrics) }
                if mode == .apps {
                    let tracker = UsageTracker.shared
                    for i in self.items.indices {
                        if let app = NSRunningApplication(processIdentifier: self.items[i].pid) {
                            self.items[i].lastUsed = tracker.lastUsed(app)
                        }
                    }
                    self.sortItems()
                }
                self.loading = false
                let ids = Set(result.map(\.id))
                self.marked = self.marked.intersection(ids)
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
                     bundleID: app.bundleIdentifier,
                     title: app.localizedName ?? "Onbekend",
                     subtitle: app.isHidden ? "verborgen" : "",
                     icon: app.icon, memoryMB: tree.totalMB(app.processIdentifier), window: nil)
            }
    }

    /// Sorteert de app-lijst volgens de gekozen volgorde (vensters blijven per app gegroepeerd).
    func sortItems() {
        guard mode == .apps else { return }
        let id = selectedItem?.id
        switch sortOrder {
        case .memory: items.sort { $0.memoryMB > $1.memoryMB }
        case .cpu: items.sort { ($0.cpuPercent ?? 0, $0.memoryMB) > ($1.cpuPercent ?? 0, $1.memoryMB) }
        case .idle: items.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .name: items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        if let id, let idx = visible.firstIndex(where: { $0.id == id }) { selection = idx }
    }

    func cycleSort() {
        sortOrder = sortOrder.next
        status = "Gesorteerd op: \(sortOrder.rawValue.lowercased())"
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
                                pid: app.processIdentifier, bundleID: app.bundleIdentifier, title: title,
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
        pendingConfirm = nil
    }

    func jump(toEnd: Bool) {
        selection = toEnd ? max(0, visible.count - 1) : 0
    }

    // MARK: Live meten (CPU, geheugen, hangen)

    private func refreshMetrics() {
        guard mode == .apps, !measuring, !items.isEmpty, NSApp.isActive,
              AppDelegate.shared?.window.isVisible == true else { return }
        measuring = true
        let pids = items.map(\.pid)
        let checkHang = Self.axTrusted(prompt: false)
        DispatchQueue.global(qos: .utility).async {
            let m = Metrics.measure(pids: pids, checkHang: checkHang)
            DispatchQueue.main.async {
                self.measuring = false
                if self.mode == .apps { self.apply(m) }
            }
        }
    }

    private func apply(_ m: Metrics) {
        for i in items.indices {
            let pid = items[i].pid
            if let mem = m.memoryMB[pid] { items[i].memoryMB = mem }
            if let ns = m.cpuNanos[pid] {
                if let prev = cpuSamples[pid], m.timestamp > prev.at, ns >= prev.ns {
                    items[i].cpuPercent = Double(ns - prev.ns) / Double(m.timestamp - prev.at) * 100
                }
                cpuSamples[pid] = (ns, m.timestamp)
            }
            if m.hangChecked {
                // Pas na twee keer achter elkaar geen antwoord markeren (voorkomt valse meldingen).
                hangStrikes[pid] = m.hung.contains(pid) ? (hangStrikes[pid] ?? 0) + 1 : 0
                items[i].notResponding = (hangStrikes[pid] ?? 0) >= 2
            }
        }
    }

    // MARK: Markeren

    /// ⌘-klik: markering van één rij aan/uit.
    func toggleMark(at index: Int) {
        let v = visible
        guard v.indices.contains(index) else { return }
        let id = v[index].id
        if marked.contains(id) { marked.remove(id) } else { marked.insert(id) }
        selection = index
        updateMarkStatus()
    }

    /// ⇧↑/⇧↓: huidige rij markeren en doorschuiven (markering uitbreiden).
    func extendMark(_ delta: Int) {
        let v = visible
        guard v.indices.contains(selection) else { return }
        marked.insert(v[selection].id)
        move(delta)
        if v.indices.contains(selection) { marked.insert(v[selection].id) }
        updateMarkStatus()
    }

    /// ⌘A: alles in de lijst markeren, of — als alles al gemarkeerd is — alles wissen.
    func toggleMarkAll() {
        let ids = Set(visible.map(\.id))
        marked = ids.isSubset(of: marked) ? [] : marked.union(ids)
        updateMarkStatus()
    }

    func clearMarks() {
        marked = []
        status = ""
    }

    private func updateMarkStatus() {
        status = marked.isEmpty ? "" : "\(marked.count) gemarkeerd — spatie/⏎ sluit ze allemaal, esc wist de markering."
    }

    func toggleMode() {
        mode = (mode == .apps) ? .windows : .apps
        filter = ""
        marked = []
        status = ""
        items = []
        reload()
    }

    func closeSelected(force: Bool) {
        if !marked.isEmpty {
            closeMarked(force: force)
            return
        }
        guard let item = selectedItem else { return }
        pendingConfirm = nil
        close(item, force: force)
        items.removeAll { $0.id == item.id }
        clampSelection()
        scheduleResync()
    }

    /// Vraagt bij de eerste keer om bevestiging; geeft true als de actie nu mag.
    private func confirm(_ key: String, _ message: String) -> Bool {
        if pendingConfirm == key {
            pendingConfirm = nil
            return true
        }
        pendingConfirm = key
        status = message
        return false
    }

    /// ⌘⏎: sluit alles wat zichtbaar is in de lijst, behalve beschermde apps.
    func closeAllVisible() {
        let settings = Settings.shared
        let all = visible
        let targets = all.filter { !settings.isProtected($0.bundleID) }
        let skipped = all.count - targets.count
        guard !targets.isEmpty else {
            status = skipped > 0 ? "Alles in deze lijst is beschermd." : ""
            return
        }
        let noun = mode == .apps ? "apps" : "vensters"
        guard confirm("all", "Druk nogmaals ⌘⏎ om \(targets.count) \(noun) te sluiten"
                      + (skipped > 0 ? " (\(skipped) beschermd blijven open)." : ".")) else { return }
        closeMany(targets)
    }

    /// Opruimen: sluit álle apps behalve beschermde, ongeacht filter of tabblad.
    func cleanUp() {
        let settings = Settings.shared
        let targets = Self.regularApps().filter {
            $0.bundleIdentifier != "com.apple.finder" && !settings.isProtected($0.bundleIdentifier)
        }
        guard !targets.isEmpty else {
            status = "Niets op te ruimen — alleen beschermde apps zijn open."
            return
        }
        let protectedCount = settings.protectedApps.count
        guard confirm("cleanup", "Opruimen: druk nogmaals ⌘⌫ om \(targets.count) apps te sluiten"
                      + (protectedCount > 0 ? " (beschermde apps blijven open)." : ". Tip: bescherm apps met ⌘P.")) else { return }
        targets.forEach { _ = $0.terminate() }
        if mode == .apps {
            let pids = Set(targets.map(\.processIdentifier))
            items.removeAll { pids.contains($0.pid) }
        }
        clampSelection()
        status = "Opgeruimd: \(targets.count) apps worden afgesloten."
        scheduleResync()
    }

    private func closeMany(_ targets: [Item]) {
        targets.forEach { close($0, force: false) }
        let ids = Set(targets.map(\.id))
        items.removeAll { ids.contains($0.id) }
        filter = ""
        clampSelection()
        status = "\(targets.count) gesloten."
        scheduleResync()
    }

    /// Sluit alle gemarkeerde items. Beschermde apps worden overgeslagen,
    /// tenzij je er precies één hebt gemarkeerd.
    private func closeMarked(force: Bool) {
        let settings = Settings.shared
        let chosen = items.filter { marked.contains($0.id) }
        let targets = chosen.count == 1 ? chosen : chosen.filter { !settings.isProtected($0.bundleID) }
        let skipped = chosen.count - targets.count
        pendingConfirm = nil
        targets.forEach { close($0, force: force) }
        let ids = Set(targets.map(\.id))
        items.removeAll { ids.contains($0.id) }
        marked = []
        clampSelection()
        status = "\(targets.count) gesloten" + (skipped > 0 ? ", \(skipped) beschermd overgeslagen." : ".")
        scheduleResync()
    }

    /// ⌘P: bescherm de app van het geselecteerde item (of haal de bescherming weg).
    func toggleProtectSelected() {
        guard let item = selectedItem else { return }
        guard let id = item.bundleID else {
            status = "Deze app kan niet beschermd worden (geen bundle-ID)."
            return
        }
        let appName = NSRunningApplication(processIdentifier: item.pid)?.localizedName ?? item.title
        let now = Settings.shared.toggleProtected(id)
        status = now ? "📌 \(appName) is beschermd en wordt niet meer meegesloten."
                     : "\(appName) is niet meer beschermd."
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

