import AppKit
import SwiftUI
import QuickLookThumbnailing

// 绳子上挂的一张截图或一段录屏
struct LineItem: Identifiable {
    let url: URL
    let date: Date
    let preview: NSImage?
    let fromClipboard: Bool     // 原来只在剪贴板里、没存成文件的截图

    var id: String { url.path }
    var isVideo: Bool { ["mov", "mp4"].contains(url.pathExtension.lowercased()) }

    // 今天的显示时间，更早的显示日期
    var title: String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month().day())
    }

    // 由 id 算出来的固定数字，用来让每张图晃的幅度、快慢都不一样
    var seed: Int { id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } }
}

@MainActor
final class LineStore: ObservableObject {
    @Published var items: [LineItem] = []

    static let maxItems = 20
    private var thumbs: [URL: NSImage] = [:]                         // 缩略图（算过就存起来）
    private var lastClipboardChange = NSPasteboard.general.changeCount

    // 只在剪贴板里的截图，帮你存一份到这里（“图片”文件夹里的“晾衣绳”）
    let clipboardFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/晾衣绳", isDirectory: true)

    func start() {
        Task {
            while true {
                saveClipboardScreenshot()
                await refresh()
                try? await Task.sleep(for: .seconds(1))   // 每秒看一次
            }
        }
    }

    func refresh() async {
        // 有图片正在飞走时先不刷新，免得动画飞到一半被打断
        guard leaving.isEmpty else { return }
        // 存成文件的截图/录屏 + 从剪贴板帮你存下来的截图，合在一起按时间排，取最新 20 个
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
        // 有变化才更新，免得界面一直重画（等缩略图的时候如果开始删东西了，这次也不更新）
        guard leaving.isEmpty else { return }
        if newItems.map(\.id) != items.map(\.id) || newItems.map({ $0.preview == nil }) != items.map({ $0.preview == nil }) {
            items = newItems
        }
    }

    // MARK: 剪贴板里的截图

    // 截图只放进剪贴板时（比如 ⌃⇧⌘4，或微信截图），帮你存成文件，这样也能挂上去
    private func saveClipboardScreenshot() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChange else { return }
        lastClipboardChange = pasteboard.changeCount

        // 只要“纯图片”：截图到剪贴板就是这样。
        // 从网页、访达里复制的东西会带着网址、文件或文字，不算截图。
        let types = Set(pasteboard.types ?? [])
        let notScreenshot: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .html, .string, .rtf]
        guard types.contains(.png) || types.contains(.tiff),
              notScreenshot.allSatisfy({ !types.contains($0) }),
              let data = pngData(from: pasteboard) else { return }

        try? FileManager.default.createDirectory(at: clipboardFolder, withIntermediateDirectories: true)
        let name = "剪贴板截屏 " + Self.nameFormatter.string(from: Date()) + ".png"
        try? data.write(to: clipboardFolder.appendingPathComponent(name))
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    // MARK: 存成文件的截图

    // 截图默认存在桌面；如果你在“截屏”App 里改过位置，就读那个位置
    private func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private func files(in folder: URL, onlyScreenshots: Bool) -> [(URL, Date)] {
        let prefixes = ["截屏", "录屏", "屏幕快照", "屏幕录制", "Screenshot", "Screen Shot", "Screen Recording"]
        let types = ["png", "jpg", "jpeg", "heic", "mov", "mp4"]
        let all = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []

        return all.compactMap { url in
            guard types.contains(url.pathExtension.lowercased()) else { return nil }
            if onlyScreenshots, !prefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (url, date)
        }
    }

    // 图片和视频都能用系统的 Quick Look 生成缩略图
    private func thumbnail(for url: URL) async -> NSImage? {
        if let cached = thumbs[url] { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 160, height: 100), scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        thumbs[url] = rep.nsImage
        return rep.nsImage
    }

    // MARK: 点击和右键菜单

    func open(_ item: LineItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: LineItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // 删除：先把文件移到废纸篓（还能拿回来），图片翻两圈、被风吹到远方，飞完了才从绳子上拿掉
    nonisolated static let deleteDuration = 3.2
    @Published private(set) var leaving: Set<String> = []     // 正在飞走的图片

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

    // MARK: 把文件拖到别的软件里（微信、Word……）

    weak var hostView: NSView?                 // 晾衣绳所在的那个视图，开始拖动要用
    private let dragSource = FileDragSource()

    // 开始成功返回 true
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
