import AppKit

// MARK: - Bijhouden wanneer je een app voor het laatst gebruikte

/// Onthoudt per app wanneer hij voor het laatst op de voorgrond stond.
/// Werkt vanaf het moment dat Sluiter draait — zet daarom "starten bij inloggen" aan.
final class UsageTracker {
    static let shared = UsageTracker()

    let startedAt = Date()
    private var lastUsed: [pid_t: Date] = [:]
    private var observers: [Any] = []

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.lastUsed[app.processIdentifier] = Date()
            })
        }
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.lastUsed[app.processIdentifier] = nil
        })
        if let front = NSWorkspace.shared.frontmostApplication {
            lastUsed[front.processIdentifier] = Date()
        }
    }

    /// Laatste gebruik; valt terug op het startmoment van de app als die na Sluiter is geopend.
    func lastUsed(_ app: NSRunningApplication) -> Date? {
        if let d = lastUsed[app.processIdentifier] { return d }
        if app.isActive { return Date() }
        if let launched = app.launchDate, launched > startedAt { return launched }
        return nil // onbekend: al open vóór Sluiter startte en sindsdien niet gebruikt
    }

    /// Bv. "zojuist", "12 min. geleden", "niet gebruikt sinds 09:14".
    func describe(_ date: Date?) -> String {
        guard let date else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "nl_NL")
            f.dateFormat = Calendar.current.isDateInToday(startedAt) ? "HH:mm" : "d MMM HH:mm"
            return "niet gebruikt sinds \(f.string(from: startedAt))"
        }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "zojuist gebruikt" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.unitsStyle = .short
        return "gebruikt " + f.localizedString(for: date, relativeTo: Date())
    }
}
