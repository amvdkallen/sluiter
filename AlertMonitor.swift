import AppKit
import UserNotifications

// MARK: - Waarschuwingen op de achtergrond

/// Controleert elke 30 seconden (ook als het venster dicht is) of een app te veel geheugen
/// gebruikt, blijft hangen, of dat de Mac geheugentekort heeft — en stuurt dan een melding
/// met een knop om de app direct te sluiten.
final class AlertMonitor: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertMonitor()

    private let center = UNUserNotificationCenter.current()
    private var timer: Timer?
    private var lastAlert: [String: Date] = [:]       // sleutel → tijdstip (om spam te voorkomen)
    private var hangStrikes: [pid_t: Int] = [:]
    private var checking = false
    private let repeatAfter: TimeInterval = 60 * 60   // per app hooguit één melding per uur

    private enum Action {
        static let quit = "QUIT"
        static let forceQuit = "FORCE_QUIT"
        static let open = "OPEN_SLUITER"
    }

    func start() {
        center.delegate = self
        let quit = UNNotificationAction(identifier: Action.quit, title: "Sluiten")
        let force = UNNotificationAction(identifier: Action.forceQuit, title: "Geforceerd stoppen", options: [.destructive])
        let open = UNNotificationAction(identifier: Action.open, title: "Open Sluiter", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "APP", actions: [quit, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "HUNG", actions: [force, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "SYSTEM", actions: [open], intentIdentifiers: []),
        ])
        reschedule()
    }

    /// Opnieuw instellen na het wijzigen van de instellingen.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard Settings.shared.alertsEnabled else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        guard !checking else { return }
        checking = true
        let settings = Settings.shared
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }
        let pids = apps.map(\.processIdentifier)
        let checkHang = AXIsProcessTrusted()
        DispatchQueue.global(qos: .utility).async {
            let m = Metrics.measure(pids: pids, checkHang: checkHang)
            let stats = SystemStats.measure(previous: nil)
            DispatchQueue.main.async {
                self.checking = false
                self.evaluate(apps: apps, metrics: m, stats: stats, settings: settings)
            }
        }
    }

    private func evaluate(apps: [NSRunningApplication], metrics m: Metrics, stats: SystemStats, settings: Settings) {
        let thresholdMB = settings.alertThresholdGB * 1024
        for app in apps {
            let pid = app.processIdentifier
            let name = app.localizedName ?? "Een app"

            if m.hangChecked {
                hangStrikes[pid] = m.hung.contains(pid) ? (hangStrikes[pid] ?? 0) + 1 : 0
                if (hangStrikes[pid] ?? 0) >= 2 {
                    notify(key: "hung-\(pid)", category: "HUNG", pid: pid,
                           title: "\(name) reageert niet",
                           body: "Deze app hangt al minstens een minuut. Geforceerd stoppen maakt je Mac weer vrij.")
                }
            }

            if let mb = m.memoryMB[pid], mb >= thresholdMB, !settings.isProtected(app.bundleIdentifier) {
                notify(key: "mem-\(pid)", category: "APP", pid: pid,
                       title: "\(name) gebruikt \(String(format: "%.1f", mb / 1024)) GB geheugen",
                       body: "Sluit hem om je Mac sneller te maken.")
            }
        }

        if settings.alertOnPressure, stats.pressure != .normal {
            let biggest = apps
                .filter { !settings.isProtected($0.bundleIdentifier) }
                .max { (m.memoryMB[$0.processIdentifier] ?? 0) < (m.memoryMB[$1.processIdentifier] ?? 0) }
            let hint = biggest.map { app -> String in
                let gb = (m.memoryMB[app.processIdentifier] ?? 0) / 1024
                return " Grootste: \(app.localizedName ?? "?") (\(String(format: "%.1f", gb)) GB)."
            } ?? ""
            notify(key: "pressure", category: "SYSTEM", pid: nil,
                   title: stats.pressure == .critical ? "Je Mac heeft ernstig geheugentekort" : "Je Mac krijgt geheugentekort",
                   body: "Sluit een paar apps om hem weer vlot te maken." + hint)
        }
    }

    private func notify(key: String, category: String, pid: pid_t?, title: String, body: String) {
        if let last = lastAlert[key], Date().timeIntervalSince(last) < repeatAfter { return }
        lastAlert[key] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        if let pid { content.userInfo = ["pid": Int(pid)] }
        center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Ook meldingen tonen als Sluiter zelf op de voorgrond staat.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let pid = (response.notification.request.content.userInfo["pid"] as? Int).map { pid_t($0) }
        DispatchQueue.main.async {
            switch response.actionIdentifier {
            case Action.quit:
                if let pid { _ = NSRunningApplication(processIdentifier: pid)?.terminate() }
            case Action.forceQuit:
                if let pid { _ = NSRunningApplication(processIdentifier: pid)?.forceTerminate() }
            default: // Open Sluiter of op de melding geklikt
                AppDelegate.shared?.show()
            }
            completionHandler()
        }
    }
}
