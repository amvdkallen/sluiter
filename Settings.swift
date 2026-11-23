import Foundation
import Combine

// MARK: - Instellingen (bewaard in UserDefaults)

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// Bundle-ID's van apps die nooit worden meegesloten bij Opruimen / alles sluiten.
    @Published var protectedApps: Set<String> {
        didSet { defaults.set(Array(protectedApps).sorted(), forKey: "protectedApps") }
    }

    private init() {
        protectedApps = Set(defaults.stringArray(forKey: "protectedApps") ?? [])
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
}
