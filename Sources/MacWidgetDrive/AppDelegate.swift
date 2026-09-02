import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowManager: DesktopWindowManager?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        let manager = DesktopWindowManager(appState: AppState.shared)
        manager.setup()
        windowManager = manager

        TrafficScheduler.shared.start()
        setupStatusItem()

        LoginItem.syncWithStoredPreference()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Main menu

    /// Accessory (menu-bar-only) apps get no main menu by default, which means
    /// there's no Edit menu to route Cmd-C/Cmd-V/Cmd-X/Cmd-A key equivalents to
    /// the first responder — so those shortcuts silently do nothing in any
    /// text field. A minimal Edit menu restores standard text editing.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "car.fill", accessibilityDescription: "Widget Drive")

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc func refreshNow() {
        AppState.shared.refreshNow()
    }

    @objc func toggleEnabled() {
        AppState.shared.isEnabled.toggle()
    }

    @objc func toggleDragMode() {
        windowManager?.toggleDragMode()
    }

    @objc func showRoute() {
        let appState = AppState.shared
        TrafficService.openDirectionsInMaps(origin: appState.originAddress, destination: appState.destinationAddress)
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(appState: AppState.shared)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Widget Drive Settings"
            win.contentView = NSHostingView(rootView: view)
            win.center()
            let wc = NSWindowController(window: win)
            wc.shouldCascadeWindows = false
            settingsWindowController = wc

            // Release when closed so settings re-opens fresh next time.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: win, queue: .main
            ) { [weak self] _ in
                self?.settingsWindowController = nil
            }
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.set(enabled: !LoginItem.isEnabled)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(titleItem("Widget Drive"))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Show Route", action: #selector(showRoute), keyEquivalent: ""))

        let minutes = AppState.shared.refreshIntervalMinutes
        let enabledItem = NSMenuItem(
            title: "Check Every \(minutes) Minute\(minutes == 1 ? "" : "s")",
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        enabledItem.state = AppState.shared.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let moveTitle = (windowManager?.isDragging ?? false) ? "Done Moving Widget" : "Move Widget…"
        menu.addItem(NSMenuItem(title: moveTitle, action: #selector(toggleDragMode), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Bold, non-clickable title shown at the top of the menu.
    private func titleItem(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        it.isEnabled = false
        return it
    }
}
