import Foundation
import Combine
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Instellingen (bewaard in UserDefaults)

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// Bundle-ID's van apps die nooit worden meegesloten bij Opruimen / alles sluiten.
    @Published var protectedApps: Set<String> {
        didSet { defaults.set(Array(protectedApps).sorted(), forKey: "protectedApps") }
    }

    // Sneltoets
    @Published var hotKeyCode: Int { didSet { defaults.set(hotKeyCode, forKey: "hotKeyCode") } }
    @Published var hotKeyModifiers: Int { didSet { defaults.set(hotKeyModifiers, forKey: "hotKeyModifiers") } }
    @Published var hotKeyDisplay: String { didSet { defaults.set(hotKeyDisplay, forKey: "hotKeyDisplay") } }

    /// Venster tonen als Sluiter start (uit = stil starten, bv. bij inloggen).
    @Published var showWindowOnLaunch: Bool { didSet { defaults.set(showWindowOnLaunch, forKey: "showWindowOnLaunch") } }

    // Waarschuwingen
    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: "alertsEnabled") } }
    @Published var alertThresholdGB: Double { didSet { defaults.set(alertThresholdGB, forKey: "alertThresholdGB") } }
    @Published var alertOnPressure: Bool { didSet { defaults.set(alertOnPressure, forKey: "alertOnPressure") } }

    private init() {
        protectedApps = Set(defaults.stringArray(forKey: "protectedApps") ?? [])
        hotKeyCode = defaults.object(forKey: "hotKeyCode") as? Int ?? kVK_Space
        hotKeyModifiers = defaults.object(forKey: "hotKeyModifiers") as? Int ?? (controlKey | optionKey)
        hotKeyDisplay = defaults.string(forKey: "hotKeyDisplay") ?? "⌃⌥Spatie"
        showWindowOnLaunch = defaults.object(forKey: "showWindowOnLaunch") as? Bool ?? true
        alertsEnabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        alertThresholdGB = defaults.object(forKey: "alertThresholdGB") as? Double ?? 3
        alertOnPressure = defaults.object(forKey: "alertOnPressure") as? Bool ?? true
    }

    func isProtected(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return protectedApps.contains(id)
    }

    /// Geeft de nieuwe status terug (true = nu beschermd).
    @discardableResult
    func toggleProtected(_ bundleID: String) -> Bool {
        if protectedApps.contains(bundleID) {
            protectedApps.remove(bundleID)
            return false
        }
        protectedApps.insert(bundleID)
        return true
    }

    // MARK: Starten bij inloggen (via macOS Login Items)

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Zet starten bij inloggen aan/uit. Geeft een foutmelding terug als het misgaat.
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
            if SMAppService.mainApp.status == .requiresApproval {
                return "Keur Sluiter goed in Systeeminstellingen → Algemeen → Inloggen."
            }
            return nil
        } catch {
            objectWillChange.send()
            return "Lukt niet: \(error.localizedDescription)"
        }
    }
}
