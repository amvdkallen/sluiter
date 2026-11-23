import AppKit
import SwiftUI

// MARK: - Instellingen-venster (⌘,)

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message = ""

    var body: some View {
        Form {
            Section("Algemeen") {
                Toggle("Start Sluiter automatisch bij inloggen", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { message = settings.setLaunchAtLogin($0) ?? "" }
                ))
                Toggle("Toon het venster als Sluiter start", isOn: $settings.showWindowOnLaunch)
                    .help("Uit: Sluiter start stil op de achtergrond; open hem met de sneltoets.")
            }

            Section("Sneltoets") {
                HStack {
                    Text("Sluiter openen")
                    Spacer()
                    Button(recording ? "Druk je toetscombinatie…" : settings.hotKeyDisplay) {
                        recording ? stopRecording() : startRecording()
                    }
                    .frame(minWidth: 170)
                    if !recording && settings.hotKeyDisplay != "⌃⌥Spatie" {
                        Button("Standaard") { applyHotKey(code: 49, mods: 0x1000 | 0x0800, display: "⌃⌥Spatie") }
                    }
                }
                Text("Gebruik minstens ⌘, ⌥ of ⌃. Esc annuleert.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Beschermde apps 📌") {
                if settings.protectedApps.isEmpty {
                    Text("Nog geen. Selecteer een app in de lijst en druk ⌘P.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(settings.protectedApps.sorted(), id: \.self) { id in
                        HStack {
                            AppLabel(bundleID: id)
                            Spacer()
                            Button {
                                settings.protectedApps.remove(id)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Bescherming opheffen")
                        }
                    }
                }
            }

            if !message.isEmpty {
                Text(message).foregroundColor(.orange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        message = ""
        HotKey.shared.unregister() // anders vangt de oude sneltoets de toetsdruk weg
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { // esc
                stopRecording()
                return nil
            }
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                message = "Gebruik minstens ⌘, ⌥ of ⌃ in je sneltoets."
                return nil
            }
            let mods = HotKey.carbonModifiers(from: flags)
            let code = Int(e.keyCode)
            let display = HotKey.describe(keyCode: code, carbonModifiers: mods,
                                          characters: e.charactersIgnoringModifiers)
            applyHotKey(code: code, mods: mods, display: display)
            return nil
        }
    }

    private func applyHotKey(code: Int, mods: Int, display: String) {
        if HotKey.shared.register(keyCode: code, carbonModifiers: mods) {
            settings.hotKeyCode = code
            settings.hotKeyModifiers = mods
            settings.hotKeyDisplay = display
            message = ""
        } else {
            message = "\(display) is al in gebruik door een andere app. Kies een andere."
        }
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        // Zorg dat er altijd een werkende sneltoets is.
        HotKey.shared.register(keyCode: settings.hotKeyCode, carbonModifiers: settings.hotKeyModifiers)
    }
}

/// Naam + icoon van een app op basis van bundle-ID.
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
        }
    }
}
