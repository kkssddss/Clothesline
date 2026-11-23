import AppKit
import SwiftUI
import ServiceManagement

@main
@MainActor
struct ClotheslineApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private let store = LineStore()
    private let menu = NSMenu()
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        makePanel()
        makeMenuBarButton()
        store.start()
    }

    // A transparent, always-on-top window along the top of the screen. The clothesline is drawn inside it.
    // It starts at the very top of the screen (covering the menu bar) so pictures can fly all the way off the screen.
    private func makePanel() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame                          // the screen minus the menu bar and Dock
        let menuBarHeight = screen.frame.maxY - area.maxY
        let height: CGFloat = menuBarHeight + 240
        panel = NSPanel(
            contentRect: NSRect(x: area.minX, y: screen.frame.maxY - height, width: area.width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar                // above the menu bar, so flying pictures aren't hidden by it
        panel.isOpaque = false
        panel.backgroundColor = .clear          // transparent: clicks pass through empty areas (the menu bar still works)
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]  // on every desktop

        let hosting = NSHostingView(rootView: ClotheslineView(store: store, topInset: menuBarHeight))
        hosting.sizingOptions = []              // don't let SwiftUI resize the window
        panel.contentView = hosting
        store.hostView = hosting                // needed to drag files into other apps
        panel.orderFrontRegardless()
    }

    // The 🧺 in the menu bar: click to show/hide, long-press (or right-click) for the menu
    private func makeMenuBarButton() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.title = "🧺"

        let press = PressView(frame: button.bounds)
        press.autoresizingMask = [.width, .height]
        press.onClick = { [weak self] in self?.toggle() }
        press.onLongPress = { [weak self] in self?.showMenu() }
        button.addSubview(press)

        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }
}

// A transparent view over the 🧺 that tells a click from a long press
final class PressView: NSView {
    var onClick: () -> Void = {}
    var onLongPress: () -> Void = {}
    private var timer: Timer?
    private var didLongPress = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        didLongPress = false
        (superview as? NSButton)?.highlight(true)
        // holding longer than 0.45 s counts as a long press
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.didLongPress = true
                (self.superview as? NSButton)?.highlight(false)
                self.onLongPress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func mouseUp(with event: NSEvent) {
        timer?.invalidate()
        timer = nil
        (superview as? NSButton)?.highlight(false)
        if !didLongPress { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        onLongPress()
    }
}
