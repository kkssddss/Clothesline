#!/bin/bash
# Makes Clothesline in one step: writes all the source code to ~/code/Clothesline, then builds, installs and opens it.
# Usage (in Terminal): bash install.sh
# To use another folder: bash install.sh /path/to/folder
set -euo pipefail

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools aren't installed. First run this in Terminal: xcode-select --install"
    echo "When they're installed, run bash install.sh again."
    exit 1
fi

DIR="${1:-$HOME/code/Clothesline}"
echo "Writing the source code to $DIR..."
mkdir -p "$DIR/Sources/Clothesline"
cd "$DIR"

cat > 'Package.swift' <<'CLOTHESLINE_FILE_END'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clothesline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clothesline")
    ]
)
CLOTHESLINE_FILE_END

cat > 'Sources/Clothesline/App.swift' <<'CLOTHESLINE_FILE_END'
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
CLOTHESLINE_FILE_END

cat > 'Sources/Clothesline/LineStore.swift' <<'CLOTHESLINE_FILE_END'
import AppKit
import SwiftUI
import QuickLookThumbnailing

// One screenshot or screen recording on the line
struct LineItem: Identifiable {
    let url: URL
    let date: Date
    let preview: NSImage?
    let fromClipboard: Bool     // a screenshot that was only on the clipboard, never saved as a file

    var id: String { url.path }
    var isVideo: Bool { ["mov", "mp4"].contains(url.pathExtension.lowercased()) }

    // Today's items show the time, older ones the date, always in English (e.g. "14:05", "Nov 22")
    var title: String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_GB")))
            : date.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US")))
    }

    // A fixed number from the id, so each picture sways by a different amount and speed
    var seed: Int { id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } }
}

@MainActor
final class LineStore: ObservableObject {
    @Published var items: [LineItem] = []

    static let maxItems = 20
    private var thumbs: [URL: NSImage] = [:]                         // thumbnails, cached once made
    private var lastClipboardChange = NSPasteboard.general.changeCount

    // Clipboard-only screenshots are saved here (a Clothesline folder in Pictures)
    let clipboardFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/Clothesline", isDirectory: true)

    func start() {
        Task {
            while true {
                saveClipboardScreenshot()
                await refresh()
                try? await Task.sleep(for: .seconds(1))   // check once a second
            }
        }
    }

    func refresh() async {
        // Don't refresh while a picture is flying away, so the animation isn't cut off
        guard leaving.isEmpty else { return }
        // Saved screenshots/recordings plus saved clipboard screenshots, sorted by time, newest 20
        var found: [URL: Date] = [:]
        for (url, date) in files(in: screenshotFolder(), onlyScreenshots: true) { found[url] = date }
        for (url, date) in files(in: clipboardFolder, onlyScreenshots: false) { found[url] = date }
        let latest = found.sorted { $0.value > $1.value }.prefix(Self.maxItems)

        var newItems: [LineItem] = []
        for (url, date) in latest {
            newItems.append(LineItem(
                url: url, date: date, preview: await thumbnail(for: url),
                fromClipboard: url.deletingLastPathComponent().path == clipboardFolder.path))
        }
        // Update only when something changed, so the view doesn't keep redrawing (and skip this round if a delete started while thumbnails were loading)
        guard leaving.isEmpty else { return }
        if newItems.map(\.id) != items.map(\.id) || newItems.map({ $0.preview == nil }) != items.map({ $0.preview == nil }) {
            items = newItems
        }
    }

    // MARK: Clipboard screenshots

    // When a screenshot only goes to the clipboard (e.g. ⌃⇧⌘4 or WeChat's screenshot tool), save it as a file so it can hang on the line too
    private func saveClipboardScreenshot() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChange else { return }
        lastClipboardChange = pasteboard.changeCount

        // Only plain images count: that's what a screenshot on the clipboard looks like.
        // Things copied from web pages or Finder come with a URL, file or text, so they don't count.
        let types = Set(pasteboard.types ?? [])
        let notScreenshot: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .html, .string, .rtf]
        guard types.contains(.png) || types.contains(.tiff),
              notScreenshot.allSatisfy({ !types.contains($0) }),
              let data = pngData(from: pasteboard) else { return }

        try? FileManager.default.createDirectory(at: clipboardFolder, withIntermediateDirectories: true)
        let name = "Clipboard Screenshot " + Self.nameFormatter.string(from: Date()) + ".png"
        try? data.write(to: clipboardFolder.appendingPathComponent(name))
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    // MARK: Saved screenshots

    // Screenshots go to the Desktop by default; if you picked another location in the Screenshot app, use that
    private func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private func files(in folder: URL, onlyScreenshots: Bool) -> [(URL, Date)] {
        let types = ["png", "jpg", "jpeg", "heic", "mov", "mp4"]
        let all = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []

        return all.compactMap { url in
            guard types.contains(url.pathExtension.lowercased()) else { return nil }
            if onlyScreenshots, !Self.isScreenCapture(url) { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (url, date)
        }
    }

    // macOS marks every screenshot with a hidden tag, whatever language the Mac uses.
    // Screen recordings may not have the tag, so also accept files whose names carry a date and time:
    // that's how macOS names screenshots and recordings in every language ("Screenshot 2026-11-23 at 14.05.09").
    private static func isScreenCapture(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 { return true }
        let stamp = #"\d{4}-\d{2}-\d{2}.*\d{1,2}\.\d{2}\.\d{2}"#
        return url.lastPathComponent.range(of: stamp, options: .regularExpression) != nil
    }

    // Quick Look makes thumbnails for both pictures and videos
    private func thumbnail(for url: URL) async -> NSImage? {
        if let cached = thumbs[url] { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 160, height: 100), scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        thumbs[url] = rep.nsImage
        return rep.nsImage
    }

    // MARK: Click and right-click menu

    func open(_ item: LineItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: LineItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // Delete: move the file to the Trash (so it can be recovered), flip the picture twice and blow it away,
    // and take it off the line only after it's gone
    nonisolated static let deleteDuration = 2.6
    @Published private(set) var leaving: Set<String> = []     // pictures currently flying away

    func delete(_ item: LineItem) {
        guard !leaving.contains(item.id) else { return }
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        thumbs[item.url] = nil
        leaving.insert(item.id)
        Task {
            try? await Task.sleep(for: .seconds(Self.deleteDuration))
            items.removeAll { $0.id == item.id }
            leaving.remove(item.id)
        }
    }

    // MARK: Dragging files into other apps (WeChat, Word...)

    weak var hostView: NSView?                 // the view the clothesline lives in, needed to start a drag
    private let dragSource = FileDragSource()

    // returns true if the drag started
    func beginFileDrag(_ item: LineItem) -> Bool {
        guard let view = hostView, let event = NSApp.currentEvent,
              event.type == .leftMouseDragged else { return false }
        let image = item.preview ?? NSWorkspace.shared.icon(forFile: item.url.path)
        let scale = min(1, 120 / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let point = view.convert(event.locationInWindow, from: nil)
        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        dragItem.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                         width: size.width, height: size.height), contents: image)
        view.beginDraggingSession(with: [dragItem], event: event, source: dragSource)
        return true
    }
}

@MainActor
final class FileDragSource: NSObject, NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
CLOTHESLINE_FILE_END

cat > 'Sources/Clothesline/ClotheslineView.swift' <<'CLOTHESLINE_FILE_END'
import SwiftUI
import UniformTypeIdentifiers

struct ClotheslineView: View {
    @ObservedObject var store: LineStore
    var topInset: CGFloat = 0          // height taken by the menu bar at the top of the window

    var body: some View {
        GeometryReader { geo in
            let rope = Rope(width: geo.size.width, topY: topInset + 44)

            ZStack(alignment: .topLeading) {
                // The hanging screenshots and recordings; scrolls sideways when there are too many
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(store.items) { item in
                            HangingCard(item: item)
                                .onTapGesture { store.open(item) }
                                .contextMenu {
                                    Button("Open") { store.open(item) }
                                    Button("Show in Finder") { store.revealInFinder(item) }
                                    Divider()
                                    Button("Move to Trash", role: .destructive) { store.delete(item) }
                                }
                                .modifier(PullUpToDelete(item: item, store: store,
                                                         leaving: store.leaving.contains(item.id)))
                                .modifier(Sway(seed: item.seed))
                                // Using its position on screen: tilt to match that part of the rope, then move down to the rope's height,
                                // so the picture's top edge sits right on the rope
                                .visualEffect { content, proxy in
                                    let x = proxy.frame(in: .global).midX
                                    return content
                                        .rotationEffect(.radians(rope.angle(at: x)), anchor: .top)
                                        .offset(y: rope.y(at: x) - rope.topY)
                                }
                                // New pictures fade in. A deleted one is already out of sight when its animation ends, so just remove it
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                                                        removal: .identity))
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, rope.topY - 2)          // picture tops sit on the rope (2 pt higher, so the rope covers the top edge)
                    .padding(.bottom, rope.sag + 12)
                }
                .scrollClipDisabled()                      // flying pictures can leave the scroll area

                // The rope (drawn in front of the pictures)
                RopeShape(rope: rope)
                    .stroke(Color(red: 0.66, green: 0.52, blue: 0.38),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .overlay(
                        RopeShape(rope: rope)
                            .stroke(Color.white.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .allowsHitTesting(false)

                // The animals
                AnimalsView(rope: rope)
            }
        }
        .animation(.spring(duration: 0.5), value: store.items.map(\.id))
    }
}

// Hold a picture to drag it anywhere; it follows the mouse:
//   pull it up more than 70 pt and let go → delete (flips twice, blows away)
//   let go before that → springs back onto the rope
//   drag it down → drop the file into another app (WeChat, Word...)
struct PullUpToDelete: ViewModifier {
    let item: LineItem
    let store: LineStore
    let leaving: Bool                           // flying away
    @State private var pull: CGSize = .zero
    @State private var flight = 0.0             // fly-away animation progress (0 to 1)
    @State private var draggingFile = false
    @GestureState private var pressing = false  // still held down (turns false by itself if the drag is interrupted)
    private let threshold: CGFloat = 70

    func body(content: Content) -> some View {
        let ready = pull.height < -threshold && !leaving
        content
            .overlay(alignment: .top) {
                if ready {
                    // Pulled far enough: a small trash can shows that letting go deletes it
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.red.opacity(0.85), in: Circle())
                        .offset(y: -12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(ready ? 1.06 : 1)
            .animation(.spring(duration: 0.2), value: ready)      // animate only the trash can and the zoom, not the drag itself
            .offset(pull)                                          // follow the mouse
            .modifier(FloatAway(progress: flight))
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        guard !leaving, !draggingFile else { return }
                        let t = value.translation
                        // Clearly dragging down: drag the file out instead
                        if t.height > 28, t.height > abs(t.width), store.beginFileDrag(item) {
                            draggingFile = true
                            withAnimation(.spring(duration: 0.3)) { pull = .zero }
                            return
                        }
                        pull = CGSize(width: t.width, height: t.height > 0 ? t.height * 0.4 : t.height)
                    }
                    .onEnded { value in
                        guard !leaving, !draggingFile else { return }
                        if value.translation.height < -threshold {
                            store.delete(item)                     // fly away from where it was pulled to
                        } else {
                            springBack()
                        }
                    }
            )
            .allowsHitTesting(!leaving)
            .onChange(of: pressing) { _, isPressing in
                // Released (or the drag was interrupted): spring back unless it's flying away
                if !isPressing {
                    draggingFile = false
                    if !store.leaving.contains(item.id) && pull != .zero { springBack() }
                }
            }
            .onChange(of: leaving, initial: true) { _, isLeaving in
                if isLeaving && flight == 0 {
                    withAnimation(.linear(duration: LineStore.deleteDuration)) { flight = 1 }
                }
            }
    }

    private func springBack() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pull = .zero }
    }
}

// Delete animation: flips over twice, then a light wind carries it off, shrinking as it goes (kept small so it's easy on the eyes)
struct FloatAway: ViewModifier, Animatable {
    var progress: Double     // 0 = hanging, 1 = gone

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        // First 45%: flip over twice (slow-fast-slow), shrinking while flipping, with almost no perspective so it never suddenly grows.
        // After the two flips it tips another 78° and lies flat, like a sheet of paper carried by the wind
        let a = min(p / 0.45, 1)
        let flip = a * a * (3 - 2 * a)
        // Last 55%: lying flat, it drifts up and to the right, smaller and fainter, bobbing slightly
        let b = max(0, (p - 0.45) / 0.55)
        let scale = (1 - 0.45 * flip) * (1 - 0.92 * pow(b, 0.9))
        let x = 90 * pow(b, 1.3) + sin(b * 2 * .pi) * 8
        let y = -10 * flip - 110 * b
        let tilt = (720 + 78) * flip + sin(b * 3 * .pi) * 6
        content
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.15)
            .rotationEffect(.degrees(sin(b * 2 * .pi) * 6))
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .opacity(b < 0.65 ? 1 : 1 - (b - 0.65) / 0.35)
            .overlay {
                if p > 0 { WindStreaks(progress: p).offset(y: -30) }
            }
    }
}

// Wind: a few white streaks sweep from left to right, each curling at the end
struct WindStreaks: View {
    let progress: Double

    // Each streak: height, start, end (as fractions of the canvas), curl size, start time, line width
    private static let streaks: [(y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double)] = [
        (0.55, 0.05, 0.70, 9, 0.30, 1.4),
        (0.30, 0.15, 0.80, 7, 0.40, 1.2),
        (0.75, 0.10, 0.65, 0, 0.48, 1.0),
    ]

    var body: some View {
        Canvas { context, size in
            for streak in Self.streaks {
                let life = (progress - streak.delay) / 0.45          // each streak lasts 45% of the animation
                guard life > 0, life < 1 else { continue }
                let path = Self.path(streak, in: size).trimmedPath(from: max(0, life - 0.4), to: life)
                context.stroke(path, with: .color(.white.opacity(0.45 * sin(life * .pi))),
                               style: StrokeStyle(lineWidth: streak.width, lineCap: .round))
            }
        }
        .frame(width: 260, height: 170)
        .shadow(color: .black.opacity(0.15), radius: 1)     // faint, but still visible on light backgrounds
        .allowsHitTesting(false)
    }

    private static func path(_ s: (y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double),
                             in size: CGSize) -> Path {
        let y = s.y * size.height
        let x0 = s.from * size.width, x1 = s.to * size.width
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y))
        // wavy line to the right
        path.addCurve(to: CGPoint(x: x1, y: y - 12),
                      control1: CGPoint(x: x0 + (x1 - x0) * 0.35, y: y - 16),
                      control2: CGPoint(x: x0 + (x1 - x0) * 0.65, y: y + 10))
        // small curl at the end
        if s.curl > 0 {
            path.addArc(center: CGPoint(x: x1, y: y - 12 - s.curl), radius: s.curl,
                        startAngle: .degrees(90), endAngle: .degrees(-200), clockwise: true)
        }
        return path
    }
}

// Gentle swaying; each picture swings by a different amount and speed
struct Sway: ViewModifier {
    let seed: Int
    @State private var swinging = false

    func body(content: Content) -> some View {
        let degrees = 1.2 + Double(seed % 5) * 0.4
        let duration = 1.6 + Double(seed % 7) * 0.15
        content
            .rotationEffect(.degrees(swinging ? degrees : -degrees), anchor: .top)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    swinging = true
                }
            }
    }
}

struct HangingCard: View {
    let item: LineItem

    var body: some View {
        VStack(spacing: 3) {
            picture

            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)   // a shadow keeps it readable on the transparent background
                .lineLimit(1)
                .frame(maxWidth: 140)
        }
    }

    private func fitted(_ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // No frame, just the picture itself
    @ViewBuilder
    private var picture: some View {
        if let preview = item.preview {
            // Sized from the picture's own aspect ratio (max 140×88) so the frame matches the picture and its top edge is at the top
            let size = fitted(preview.size, maxWidth: 140, maxHeight: 88)
            Image(nsImage: preview)
                .resizable()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if item.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                }
                // Screenshots that were only on the clipboard get a small badge in the bottom-right corner
                .overlay(alignment: .bottomTrailing) {
                    if item.fromClipboard {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
        } else {
            Image(systemName: item.isVideo ? "film" : "photo")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .frame(width: 88, height: 60)
        }
    }
}
CLOTHESLINE_FILE_END

cat > 'Sources/Clothesline/Rope.swift' <<'CLOTHESLINE_FILE_END'
import SwiftUI

// The rope's shape: high at both ends, sagging in the middle
struct Rope: Sendable {
    var width: CGFloat
    var topY: CGFloat = 44      // height of the ends (leaves room above for the animals)
    var sag: CGFloat = 38       // how far the middle sags

    // rope height at x
    func y(at x: CGFloat) -> CGFloat {
        guard width > 0 else { return topY }
        let u = (x - width / 2) / (width / 2)          // -1 at the left end, 0 in the middle, 1 at the right end
        return topY + sag * (1 - u * u)
    }

    // rope angle at x (animals standing there tilt to match)
    func angle(at x: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let half = width / 2
        return atan(-sag * 2 * (x - half) / (half * half))
    }
}

struct RopeShape: Shape {
    let rope: Rope

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rope.topY))
        // A control point at twice the sag draws exactly the y(at:) curve above
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rope.topY),
                          control: CGPoint(x: rect.width / 2, y: rope.topY + rope.sag * 2))
        return path
    }
}
CLOTHESLINE_FILE_END

cat > 'Sources/Clothesline/Animals.swift' <<'CLOTHESLINE_FILE_END'
import SwiftUI
import Observation

// Little animals walking back and forth on the rope.
// Drawn entirely in code with circles and ovals, on a 24×18 grid, facing right.
// Walking has two frames: the legs close and open, and the body lifts a little on the open frame.
// Now and then an animal stops to graze.

enum AnimalKind {
    case sheep, pig, cow, rooster
}

enum Pose {
    case walk0     // legs together
    case walk1     // legs apart (the body lifts a little)
    case nibble    // stopped, head down, grazing
}

// MARK: - The herd (moves every 70 ms)

@MainActor
@Observable
final class Herd {
    struct Member: Identifiable {
        let id: Int
        let kind: AnimalKind
        let scale: Double          // screen points per grid unit (the lamb is smaller)
        var x: Double
        var facing: Double         // 1 = facing right, -1 = facing left
        var nibble = 0             // ticks of grazing left
        var step = 0               // steps walked

        var pose: Pose { nibble > 0 ? .nibble : (step % 2 == 1 ? .walk1 : .walk0) }
        var bob: Double { pose == .walk1 ? -1 : 0 }
    }

    static let tick = 0.07                 // one tick = 70 ms
    static let stepTicks = 3               // switch legs every 3 ticks
    static let speed = 16.0                // grid units walked per second
    static let nibbleChance = 0.004        // 0.4% chance per tick of stopping to graze
    static let nibbleTicks = 18...36       // graze for 1.3 to 2.5 seconds

    var members: [Member] = []
    @ObservationIgnored var width: Double = 0
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var timer: Timer?

    func start(width: Double) {
        self.width = width
        guard timer == nil else { return }
        // Two sheep (one is a lamb), a pig, a cow and a rooster
        let lineup: [(AnimalKind, Double)] = [(.sheep, 2.0), (.sheep, 1.5), (.pig, 2.0), (.cow, 2.1), (.rooster, 1.9)]
        members = lineup.shuffled().enumerated().map { index, animal in
            Member(id: index, kind: animal.0, scale: animal.1,
                   x: .random(in: 60...max(61, width - 60)), facing: Bool.random() ? 1 : -1)
        }
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        ticks += 1
        let left = 30.0, right = width - 30
        for i in members.indices {
            var m = members[i]
            if m.nibble > 0 {
                m.nibble -= 1
            } else {
                m.x += m.facing * Self.speed * m.scale * Self.tick
                if m.x >= right || m.x <= left {
                    // Reached the end: turn around and graze for a bit
                    m.x = min(max(m.x, left), right)
                    m.facing = -m.facing
                    m.nibble = Int.random(in: Self.nibbleTicks)
                } else if Double.random(in: 0..<1) < Self.nibbleChance {
                    m.nibble = Int.random(in: Self.nibbleTicks)
                }
                if ticks % Self.stepTicks == 0 { m.step += 1 }
            }
            members[i] = m
        }
    }
}

struct AnimalsView: View {
    let rope: Rope
    @State private var herd = Herd()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(herd.members) { m in
                let x = CGFloat(m.x)
                let feet = (17.2 - 9) * m.scale        // distance from the canvas center to the feet
                AnimalSprite(kind: m.kind, pose: m.pose, scale: m.scale)
                    .scaleEffect(x: m.facing, y: 1)     // drawn facing right; mirrored when walking left
                    .rotationEffect(.radians(rope.angle(at: x)), anchor: UnitPoint(x: 0.5, y: 17.2 / 18))
                    .shadow(color: .black.opacity(0.3), radius: 1.2, y: 1)
                    .position(x: x, y: rope.y(at: x) - feet + 1 + m.bob)
                    .animation(.linear(duration: Herd.tick), value: m.x)   // glide smoothly between ticks
            }
        }
        .allowsHitTesting(false)                        // animals can't be clicked; clicks pass through
        .onAppear { herd.start(width: Double(rope.width)) }
        .onChange(of: rope.width) { _, width in herd.width = Double(width) }
    }
}

// MARK: - Drawing one animal

struct AnimalSprite: View {
    let kind: AnimalKind
    let pose: Pose
    let scale: Double

    var body: some View {
        Canvas { context, _ in
            AnimalPainter(u: CGFloat(scale), pose: pose).draw(kind, in: context)
        }
        .frame(width: 24 * scale, height: 18 * scale)
    }
}

// All coordinates are grid units (24×18, origin at top left, facing right), multiplied by u when drawn
struct AnimalPainter {
    let u: CGFloat
    let pose: Pose

    static let wool = hex(0xfbfaf4), woolEdge = hex(0xa7aab2), face = hex(0x4b4f59)
    static let blush = hex(0xff9fb0), pupil = hex(0x111111)

    // legs in (1), out (-1), or even while grazing (0)
    private var legShift: CGFloat {
        switch pose {
        case .walk0: return 1
        case .walk1: return -1
        case .nibble: return 0
        }
    }
    private var nibbling: Bool { pose == .nibble }

    func draw(_ kind: AnimalKind, in ctx: GraphicsContext) {
        switch kind {
        case .sheep: sheep(ctx)
        case .pig: pig(ctx)
        case .cow: cow(ctx)
        case .rooster: rooster(ctx)
        }
    }

    // MARK: Sheep

    private func sheep(_ ctx: GraphicsContext) {
        fourLegs(ctx, color: Self.face, width: 1.7, top: 11.5)
        let puffs: [(CGFloat, CGFloat)] = [(6.5, 7.2), (9.8, 5.6), (13.4, 5.8), (16.0, 7.6), (15.2, 10.6),
                                           (11.0, 11.4), (7.0, 10.6), (4.6, 9.0), (10.8, 8.4)]
        // Draw the 9 puffs slightly larger in gray, then cover them in wool color → only a gray outline is left
        for (cx, cy) in puffs { fill(ctx, oval(cx - 3.8, cy - 3.8, cx + 3.8, cy + 3.8), Self.woolEdge) }
        for (cx, cy) in puffs { fill(ctx, oval(cx - 3.3, cy - 3.3, cx + 3.3, cy + 3.3), Self.wool) }
        let headY: CGFloat = nibbling ? 9.4 : 5.4
        fill(ctx, oval(17.4, headY, 23.2, headY + 5.6), Self.face)              // head
        fill(ctx, oval(17.0, headY + 0.4, 19.2, headY + 2.0), Self.face)        // ear
        eye(ctx, 20.9, headY + 2.0)
        fill(ctx, oval(21.0, headY + 3.6, 22.4, headY + 4.4), Self.blush)       // blush
    }

    // MARK: Pig

    private func pig(_ ctx: GraphicsContext) {
        let pink = Self.hex(0xffc8d2), edge = Self.hex(0xe48ea3), leg = Self.hex(0xf4a9b8)
        let snout = Self.hex(0xf7a3b4), nostril = Self.hex(0xc0647a)
        fourLegs(ctx, color: leg, width: 1.9, top: 10.8)
        ctx.stroke(oval(1.9, 6.0, 3.9, 8.0), with: .color(edge), lineWidth: 0.55 * u)  // curly tail
        fill(ctx, oval(3.0, 4.0, 18.0, 13.7), edge)
        fill(ctx, oval(3.5, 4.5, 17.5, 13.2), pink)                              // body
        let headY: CGFloat = nibbling ? 7.6 : 4.4
        fill(ctx, triangle((16.4, headY + 1.4), (17.2, headY - 1.4), (18.6, headY + 0.8)), leg)  // back ear
        fill(ctx, oval(15.3, headY - 0.5, 22.7, headY + 6.5), edge)
        fill(ctx, oval(15.8, headY, 22.2, headY + 6.0), pink)                    // head
        fill(ctx, triangle((17.8, headY + 1.0), (19.0, headY - 1.6), (20.2, headY + 0.8)), leg)  // front ear
        fill(ctx, oval(20.9, headY + 2.2, 23.8, headY + 4.6), snout)             // snout
        fill(ctx, oval(21.6, headY + 3.0, 22.2, headY + 3.8), nostril)
        fill(ctx, oval(22.6, headY + 3.0, 23.2, headY + 3.8), nostril)
        eye(ctx, 19.4, headY + 2.0)
        fill(ctx, oval(17.8, headY + 3.8, 19.2, headY + 4.6), Self.blush)
    }

    // MARK: Cow

    private func cow(_ ctx: GraphicsContext) {
        let white = Self.wool, edge = Self.woolEdge, spot = Self.face
        let muzzle = Self.hex(0xffc9cf), nostril = Self.hex(0xc0647a), horn = Self.hex(0xf3e2b3)
        fourLegs(ctx, color: white, width: 1.8, top: 10.5, edge: edge, hoof: spot)
        var tail = Path()                                                        // tail
        tail.move(to: pt(3.4, 6.2))
        tail.addQuadCurve(to: pt(2.2, 10.6), control: pt(1.8, 7.0))
        ctx.stroke(tail, with: .color(spot), style: StrokeStyle(lineWidth: 0.5 * u, lineCap: .round))
        fill(ctx, oval(1.5, 10.0, 2.9, 11.9), spot)
        fill(ctx, rounded(2.5, 4.1, 18.1, 13.1, 3.7), edge)
        let torso = rounded(3.0, 4.6, 17.6, 12.6, 3.2)
        fill(ctx, torso, white)                                                  // body
        var spots = ctx                                                          // black spots
        spots.clip(to: torso)
        fill(spots, oval(4.8, 5.0, 9.4, 8.8), spot)
        fill(spots, oval(10.6, 8.6, 15.0, 13.0), spot)
        fill(spots, oval(14.2, 3.8, 17.8, 7.0), spot)
        let headY: CGFloat = nibbling ? 7.6 : 3.6
        fill(ctx, oval(17.6, headY - 1.3, 18.8, headY + 0.6), horn)              // little horn
        fill(ctx, oval(20.4, headY - 1.3, 21.6, headY + 0.6), horn)
        fill(ctx, oval(15.4, headY + 0.6, 18.2, headY + 2.4), edge)
        fill(ctx, oval(15.7, headY + 0.9, 17.9, headY + 2.1), white)             // ear
        fill(ctx, oval(16.3, headY - 0.5, 22.9, headY + 6.3), edge)
        let head = oval(16.8, headY, 22.4, headY + 5.8)
        fill(ctx, head, white)                                                   // head
        var patch = ctx
        patch.clip(to: head)
        fill(patch, oval(16.0, headY - 1.0, 20.2, headY + 2.8), spot)           // black patch around the eye
        fill(ctx, oval(19.4, headY + 3.1, 23.8, headY + 6.2), muzzle)            // pink muzzle
        fill(ctx, oval(20.6, headY + 4.2, 21.2, headY + 5.0), nostril)
        fill(ctx, oval(22.0, headY + 4.2, 22.6, headY + 5.0), nostril)
        eye(ctx, 19.9, headY + 2.0)
    }

    // MARK: Rooster

    private func rooster(_ ctx: GraphicsContext) {
        let body = Self.hex(0xd9774a), edge = Self.hex(0xa9502c), wing = Self.hex(0xb85c34)
        let neck = Self.hex(0xf0a45a), neckEdge = Self.hex(0xc9783a)
        let red = Self.hex(0xe63946), yellow = Self.hex(0xf2b134)
        let feathers = [Self.hex(0x1f3d45), Self.hex(0x2f5d62), Self.hex(0x3e7a6e)]
        // Two yellow legs that also open and close, with three toes each
        for (index, lx) in [9.4, 11.8].enumerated() {
            let x0 = CGFloat(lx) + (index == 0 ? legShift : -legShift) * 0.6
            fill(ctx, rounded(x0, 12.6, x0 + 0.9, 17.2, 0.45), yellow)
            fill(ctx, rounded(x0 - 0.5, 16.5, x0 + 2.2, 17.2, 0.35), yellow)
        }
        // Big raised tail (three dark green feathers)
        fill(ctx, oval(1.0, 3.6, 8.6, 6.0, rotation: -0.95, around: (5.6, 7.6)), feathers[0])
        fill(ctx, oval(0.8, 6.0, 8.0, 8.4, rotation: -0.55, around: (5.6, 8.6)), feathers[1])
        fill(ctx, oval(1.2, 8.6, 7.8, 10.8, rotation: -0.15, around: (5.8, 9.6)), feathers[2])
        // Body and wing
        fill(ctx, oval(5.3, 6.1, 16.5, 14.9), edge)
        fill(ctx, oval(5.8, 6.6, 16.0, 14.4), body)
        fill(ctx, oval(7.2, 9.0, 12.8, 12.6), wing)
        // Neck and head (lowered while grazing)
        let dy: CGFloat = nibbling ? 3.0 : 0
        fill(ctx, oval(12.5, 4.3 + dy, 18.1, 11.5), neckEdge)
        fill(ctx, oval(13.0, 4.8 + dy, 17.6, 11.0), neck)
        fill(ctx, oval(13.1, 2.5 + dy, 18.9, 8.1 + dy), neckEdge)
        fill(ctx, oval(13.6, 3.0 + dy, 18.4, 7.6 + dy), neck)
        // Red comb and wattle, yellow beak
        fill(ctx, oval(14.0, 1.6 + dy, 15.8, 3.4 + dy), red)
        fill(ctx, oval(15.1, 1.0 + dy, 17.1, 3.0 + dy), red)
        fill(ctx, oval(16.4, 1.6 + dy, 18.0, 3.4 + dy), red)
        fill(ctx, triangle((18.2, 4.6 + dy), (20.4, 5.5 + dy), (18.2, 6.4 + dy)), yellow)
        fill(ctx, oval(17.4, 6.0 + dy, 18.8, 8.4 + dy), red)
        eye(ctx, 16.7, 4.8 + dy)
    }

    // MARK: Drawing helpers

    // Four upright legs in two pairs: one pair moves in while the other moves out
    private func fourLegs(_ ctx: GraphicsContext, color: Color, width: CGFloat, top: CGFloat,
                          edge: Color? = nil, hoof: Color? = nil) {
        for (index, lx) in [6.0, 9.0, 13.5, 16.5].enumerated() {
            let x0 = CGFloat(lx) + (index % 2 == 0 ? legShift : -legShift) * 0.6
            if let edge { fill(ctx, rounded(x0 - 0.4, top, x0 + width + 0.4, 17.6, 1.0), edge) }
            fill(ctx, rounded(x0, top, x0 + width, 17.2, 0.8), color)
            if let hoof { fill(ctx, rounded(x0, 16.0, x0 + width, 17.2, 0.6), hoof) }
        }
    }

    // White of the eye plus a pupil set slightly down and right, looking ahead
    private func eye(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        fill(ctx, oval(x - 0.9, y - 0.9, x + 0.9, y + 0.9), .white)
        fill(ctx, oval(x - 0.35, y - 0.35, x + 0.45, y + 0.45), Self.pupil)
    }

    private func fill(_ ctx: GraphicsContext, _ path: Path, _ color: Color) {
        ctx.fill(path, with: .color(color))
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

    // Oval from its top-left and bottom-right corners (like Pillow)
    private func oval(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x0 * u, y: y0 * u, width: (x1 - x0) * u, height: (y1 - y0) * u))
    }

    // Same, rotated around a point (for the rooster's tail feathers)
    private func oval(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                      rotation: CGFloat, around p: (CGFloat, CGFloat)) -> Path {
        let c = pt(p.0, p.1)
        return oval(x0, y0, x1, y1).applying(
            CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(rotationAngle: rotation))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }

    private func rounded(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x0 * u, y: y0 * u, width: (x1 - x0) * u, height: (y1 - y0) * u),
             cornerRadius: r * u)
    }

    private func triangle(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: pt(a.0, a.1))
        path.addLine(to: pt(b.0, b.1))
        path.addLine(to: pt(c.0, c.1))
        path.closeSubpath()
        return path
    }

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xff) / 255,
              green: Double((value >> 8) & 0xff) / 255,
              blue: Double(value & 0xff) / 255)
    }
}
CLOTHESLINE_FILE_END

cat > 'build-app.sh' <<'CLOTHESLINE_FILE_END'
#!/bin/bash
# Packages the program as Clothesline.app, installs it in Applications, and reopens it
# Usage: run ./build-app.sh in the project folder
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=".build/Clothesline.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Clothesline "$APP/Contents/MacOS/Clothesline"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Clothesline</string>
    <key>CFBundleIdentifier</key>
    <string>local.clothesline</string>
    <key>CFBundleExecutable</key>
    <string>Clothesline</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Reads the screenshots and screen recordings on your Desktop to hang them on the clothesline.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Quit the old version if it's running, install into Applications, and open it again.
# Without permission to write to /Applications, install into your own ~/Applications instead
DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
pkill -x Clothesline 2>/dev/null || true
rm -rf "$DEST/Clothesline.app"
cp -R "$APP" "$DEST/"
open "$DEST/Clothesline.app"
echo "Done. Installed $DEST/Clothesline.app and opened it."
CLOTHESLINE_FILE_END

cat > '.gitignore' <<'CLOTHESLINE_FILE_END'
.build/
.swiftpm/
.DS_Store
CLOTHESLINE_FILE_END

chmod +x build-app.sh
echo "Building (about 1 minute the first time)..."
./build-app.sh
