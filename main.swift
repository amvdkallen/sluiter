// Sluiter — snel openstaande apps en vensters sluiten met het toetsenbord.
import AppKit

// MARK: - Start

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
