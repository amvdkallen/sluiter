import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Darwin
import Combine

// MARK: - Venster, menu en sneltoets

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    let model = Model()
    var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var settingsWindow: NSWindow?
    private var openMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        _ = UsageTracker.shared // begin met bijhouden wanneer apps gebruikt worden
        buildMainMenu()
        buildWindow()
        buildStatusItem()
        let settings = Settings.shared
        HotKey.shared.action = { [weak self] in self?.toggle() }
        if !HotKey.shared.register(keyCode: settings.hotKeyCode, carbonModifiers: settings.hotKeyModifiers) {
            model.status = "Sneltoets \(settings.hotKeyDisplay) is bezet door een andere app — kies een andere via ⌘,"
        }
        settings.$hotKeyDisplay
            .sink { [weak self] display in self?.openMenuItem?.title = "Openen (\(display))" }
            .store(in: &cancellables)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
        if settings.showWindowOnLaunch { show() }
    }

    /// Klik op het Dock-icoon: venster weer tonen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }

    /// Elke keer dat je terugkomt in Sluiter de lijst verversen.
    func applicationDidBecomeActive(_ notification: Notification) {
        if window.isVisible { model.reload(keepSelection: true) }
    }

    /// Venster sluiten (rode knop / ⌘W) = verbergen; de sneltoets blijft werken.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Sluiter"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 360)
        window.setFrameAutosaveName("SluiterHoofdvenster")
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self

        let blur = NSVisualEffectView()
        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        blur.state = .followsWindowActiveState

        let host = NSHostingView(rootView: ContentView(model: model).padding(.top, 22))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        window.contentView = blur
        if !window.setFrameUsingName("SluiterHoofdvenster") { window.center() }
    }

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Sluiter")
        appMenu.addItem(withTitle: "Over Sluiter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Instellingen…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Verberg Sluiter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Verberg andere", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Stop Sluiter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Weergave")
        let apps = viewMenu.addItem(withTitle: "Apps", action: #selector(showApps), keyEquivalent: "1")
        let wins = viewMenu.addItem(withTitle: "Vensters", action: #selector(showWindows), keyEquivalent: "2")
        viewMenu.addItem(.separator())
        let refresh = viewMenu.addItem(withTitle: "Ververs", action: #selector(refresh), keyEquivalent: "r")
        [apps, wins, refresh].forEach { $0.target = self }

        let actionsItem = NSMenuItem()
        let actionsMenu = NSMenu(title: "Acties")
        let protect = actionsMenu.addItem(withTitle: "Beschermen aan/uit", action: #selector(protectSelected), keyEquivalent: "p")
        let cleanup = actionsMenu.addItem(withTitle: "Opruimen…", action: #selector(cleanUp), keyEquivalent: "\u{8}")
        [protect, cleanup].forEach { $0.target = self }
        actionsItem.submenu = actionsMenu
        viewItem.submenu = viewMenu
        main.addItem(viewItem)
        main.addItem(actionsItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Venster")
        winMenu.addItem(withTitle: "Sluit venster", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "Minimaliseer", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        main.addItem(winItem)
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: "Sluiter")
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Openen (\(Settings.shared.hotKeyDisplay))", action: #selector(showFromMenu), keyEquivalent: "")
        open.target = self
        openMenuItem = open
        menu.addItem(withTitle: "Instellingen…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Stop Sluiter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    @objc private func showFromMenu() { show() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Sluiter-instellingen"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func showApps() { if model.mode != .apps { model.toggleMode() } }
    @objc private func showWindows() { if model.mode != .windows { model.toggleMode() } }
    @objc private func refresh() { model.reload(keepSelection: true) }
    @objc private func protectSelected() { model.toggleProtectSelected() }
    @objc private func cleanUp() { model.cleanUp() }

    func toggle() {
        if NSApp.isActive && window.isKeyWindow { NSApp.hide(nil) } else { show() }
    }

    func show() {
        model.filter = ""
        model.status = ""
        model.selection = 0
        model.reload()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Toetsenbordafhandeling. Geeft true terug als de toets is verwerkt.
    private func handle(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)

        switch Int(e.keyCode) {
        case kVK_DownArrow: shift ? model.extendMark(1) : model.move(1)
        case kVK_UpArrow: shift ? model.extendMark(-1) : model.move(-1)
        case kVK_PageDown: model.move(10)
        case kVK_PageUp: model.move(-10)
        case kVK_Home: model.jump(toEnd: false)
        case kVK_End: model.jump(toEnd: true)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.needsPermission {
                model.requestPermission()
            } else if cmd { model.closeAllVisible() } else { model.closeSelected(force: shift) }
        case kVK_Space:
            model.closeSelected(force: shift)
        case kVK_Tab:
            model.toggleMode()
        case kVK_Escape:
            if !model.marked.isEmpty { model.clearMarks() }
            else if model.filter.isEmpty { NSApp.hide(nil) } else { model.filter = "" }
        case kVK_Delete:
            if cmd { model.cleanUp() }
            else if !model.filter.isEmpty { model.filter.removeLast() }
        default:
            if cmd && e.charactersIgnoringModifiers?.lowercased() == "p" {
                model.toggleProtectSelected()
                return true
            }
            if cmd && e.charactersIgnoringModifiers?.lowercased() == "s" {
                model.cycleSort()
                return true
            }
            if cmd && e.charactersIgnoringModifiers?.lowercased() == "a" {
                model.toggleMarkAll()
                return true
            }
            if cmd || flags.contains(.control) { return false } // laat het menu ⌘-toetsen afhandelen
            guard let chars = e.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).contains($0) })
            else { return false }
            model.filter += chars
        }
        return true
    }
}

