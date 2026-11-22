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
        app.setActivationPolicy(.accessory)   // 不在 Dock 里出现图标
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private let store = LineStore()
    private let menu = NSMenu()
    private let loginItem = NSMenuItem(title: "开机时自动打开", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        makePanel()
        makeMenuBarButton()
        store.start()
    }

    // 屏幕顶部一条透明的、永远浮在最上面的窗口，晾衣绳就画在里面。
    // 窗口从屏幕最顶上开始（盖住菜单栏那一条），这样图片往上飞的时候能一直飞出屏幕。
    private func makePanel() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame                          // 去掉菜单栏和 Dock 之后的区域
        let menuBarHeight = screen.frame.maxY - area.maxY
        let height: CGFloat = menuBarHeight + 240
        panel = NSPanel(
            contentRect: NSRect(x: area.minX, y: screen.frame.maxY - height, width: area.width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar                // 比菜单栏还高一层，飞上去的图片不会被菜单栏挡住
        panel.isOpaque = false
        panel.backgroundColor = .clear          // 透明：没挂东西的地方鼠标能点穿（菜单栏照常能点）
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]  // 每个桌面都有

        let hosting = NSHostingView(rootView: ClotheslineView(store: store, topInset: menuBarHeight))
        hosting.sizingOptions = []              // 别让 SwiftUI 改窗口大小
        panel.contentView = hosting
        store.hostView = hosting                // 把文件拖到别的软件时要用
        panel.orderFrontRegardless()
    }

    // 菜单栏上的 🧺：点一下显示/隐藏，长按（或右键）才出菜单
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
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

// 盖在 🧺 上面的一层透明视图，用来分辨“点一下”和“长按”
final class PressView: NSView {
    var onClick: () -> Void = {}
    var onLongPress: () -> Void = {}
    private var timer: Timer?
    private var didLongPress = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        didLongPress = false
        (superview as? NSButton)?.highlight(true)
        // 按住超过 0.45 秒就算长按
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
