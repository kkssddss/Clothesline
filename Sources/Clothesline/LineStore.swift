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
