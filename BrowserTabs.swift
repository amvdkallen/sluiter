import AppKit

// MARK: - Browsertabbladen (via AppleScript)

/// Verwijzing naar één tabblad in een browser.
struct TabRef {
    let bundleID: String
    let windowID: Int
    let tabID: Int?   // Chrome-familie: vast id; Safari: geen id, dan via index
    var index: Int    // 1-gebaseerd binnen het venster
}

enum BrowserTabs {
    /// Browsers met hetzelfde AppleScript-woordenboek als Chrome.
    static let chromeFamily: [String] = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.google.Chrome.beta",
    ]
    static let safari = "com.apple.Safari"

    static var supported: [String] { chromeFamily + [safari] }

    private static let fieldSep = "\u{1F}"
    private static let recordSep = "\u{1E}"

    /// Haalt alle tabbladen op uit draaiende browsers. Start nooit een browser.
    static func load() -> (items: [Item], errors: [String]) {
        var items: [Item] = []
        var errors: [String] = []
        let running = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return supported.contains(id) && !$0.isTerminated
        }
        for app in running {
            guard let bid = app.bundleIdentifier else { continue }
            let name = app.localizedName ?? bid
            let (out, err) = runAppleScript(listScript(bundleID: bid))
            if let err {
                errors.append(describe(error: err, browser: name))
                continue
            }
            for record in out.components(separatedBy: recordSep) where !record.isEmpty {
                let f = record.components(separatedBy: fieldSep)
                guard f.count >= 5, let wid = Int(f[0]), let idx = Int(f[2]) else { continue }
                let tabID = Int(f[1]).flatMap { $0 == 0 ? nil : $0 }
                let title = f[3].isEmpty || f[3] == "missing value" ? "(nieuw tabblad)" : f[3]
                let url = f[4] == "missing value" ? "" : f[4]
                let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
                let ref = TabRef(bundleID: bid, windowID: wid, tabID: tabID, index: idx)
                items.append(Item(id: "tab-\(bid)-\(wid)-\(tabID.map(String.init) ?? "i\(idx)-\(url)")",
                                  kind: .tab, pid: app.processIdentifier, bundleID: nil,
                                  title: title, subtitle: "\(name) · \(host)",
                                  icon: app.icon, memoryMB: 0, window: nil, tab: ref))
            }
        }
        return (items, errors)
    }

    /// Sluit één tabblad. Geeft een foutmelding terug als het niet lukt.
    static func close(_ ref: TabRef) -> String? {
        let target = ref.tabID.map { "tab id \($0)" } ?? "tab \(ref.index)"
        let script = "tell application id \"\(ref.bundleID)\" to close (\(target) of window id \(ref.windowID))"
        let (_, err) = runAppleScript(script)
        return err.map { describe(error: $0, browser: ref.bundleID) }
    }

    /// Brengt het tabblad naar voren (venster + tabblad activeren).
    static func focus(_ ref: TabRef) {
        let script: String
        if chromeFamily.contains(ref.bundleID) {
            script = """
            tell application id "\(ref.bundleID)"
                set w to window id \(ref.windowID)
                set active tab index of w to \(ref.index)
                set index of w to 1
                activate
            end tell
            """
        } else {
            script = """
            tell application id "\(ref.bundleID)"
                set w to window id \(ref.windowID)
                set current tab of w to tab \(ref.index) of w
                set index of w to 1
                activate
            end tell
            """
        }
        _ = runAppleScript(script)
    }

    // MARK: Scripts

    static func listScript(bundleID: String) -> String {
        let isSafari = bundleID == safari
        // Per venster alle eigenschappen in één keer ophalen (veel sneller dan per tabblad).
        return """
        set sep to character id 31
        set rs to character id 30
        set out to ""
        tell application id "\(bundleID)"
            repeat with w in windows
                try
                    set wid to id of w
                    set theTitles to \(isSafari ? "name" : "title") of tabs of w
                    set theURLs to URL of tabs of w
                    \(isSafari ? "set theIDs to {}" : "set theIDs to id of tabs of w")
                    repeat with k from 1 to count of theTitles
                        set t to ""
                        set u to ""
                        set tid to 0
                        try
                            set t to (item k of theTitles) as text
                        end try
                        try
                            set u to (item k of theURLs) as text
                        end try
                        try
                            set tid to (item k of theIDs)
                        end try
                        set out to out & wid & sep & tid & sep & k & sep & t & sep & u & rs
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
    }

    private static func describe(error: String, browser: String) -> String {
        if error.contains("-1743") || error.lowercased().contains("not authorized") || error.contains("niet bevoegd") {
            return "Geef Sluiter toestemming voor \(browser): Systeeminstellingen → Privacy → Automatisering."
        }
        if error.contains("-1728") || error.contains("-1719") {
            return "Tabblad niet gevonden (al gesloten?)."
        }
        return "\(browser): \(error.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Voert AppleScript uit via osascript (los proces: blokkeert Sluiter niet bij een trage browser).
    static func runAppleScript(_ source: String, timeout: TimeInterval = 8) -> (String, String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return ("", error.localizedDescription) }
        // Uitvoer gelijktijdig lezen: anders loopt de pijp vol bij veel tabbladen.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return ("", "reageert niet (time-out)")
        }
        p.waitUntilExit()
        let o = String(decoding: outData, as: UTF8.self)
        let e = String(decoding: errData, as: UTF8.self)
        if p.terminationStatus != 0 { return (o, e.isEmpty ? "onbekende fout" : e) }
        return (o.trimmingCharacters(in: .newlines), nil)
    }
}
