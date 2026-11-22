import AppKit
import ScreenCaptureKit
import QuickLookThumbnailing

// 绳子上挂的一样东西：要么是一个软件，要么是一个截图/录屏
struct LineItem: Identifiable {
    enum Kind {
        case app(NSRunningApplication)
        case capture(URL)
    }
    let id: String
    let kind: Kind
    let title: String
    let date: Date          // 排序用：软件=最后一次用它的时间，截图=拍下的时间
    let icon: NSImage?
    let preview: NSImage?

    var isVideo: Bool {
        ["mov", "mp4"].contains(fileURL?.pathExtension.lowercased() ?? "")
    }

    // 截图/录屏的文件位置；软件没有
    var fileURL: URL? {
        if case .capture(let url) = kind { return url }
        return nil
    }

    // 由 id 算出来的固定数字，用来让每张图晃的幅度、快慢都不一样
    var seed: Int { id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } }
}

@MainActor
final class LineStore: ObservableObject {
    @Published var items: [LineItem] = []

    private var lastUsed: [pid_t: Date] = [:]        // 每个软件最后一次在最前面的时间
    private var appPreviews: [pid_t: NSImage] = [:]  // 每个软件最近一次截到的窗口预览
    private var captureThumbs: [URL: NSImage] = [:]  // 截图/录屏的缩略图（算过就存起来）

    func start() {
        CGRequestScreenCaptureAccess()   // 第一次会弹窗要“屏幕录制”权限，用来拍窗口预览
        Task {
            while true {
                await refresh()
                try? await Task.sleep(for: .seconds(2))   // 每 2 秒刷新一次
            }
        }
    }

    func refresh() async {
        // 1. 记下现在在最前面的软件
        if let front = NSWorkspace.shared.frontmostApplication {
            lastUsed[front.processIdentifier] = Date()
        }

        // 2. 所有打开的软件（就是 Dock 里有小圆点的那些）
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        await updateAppPreviews(for: apps)

        var newItems: [LineItem] = apps.map { app in
            LineItem(
                id: "app-\(app.processIdentifier)",
                kind: .app(app),
                title: app.localizedName ?? "",
                date: lastUsed[app.processIdentifier] ?? app.launchDate ?? .distantPast,
                icon: app.icon,
                preview: appPreviews[app.processIdentifier])
        }

        // 3. 最新的 20 个截图/录屏
        for (url, date) in latestCaptures(limit: 20) {
            newItems.append(LineItem(
                id: "file-\(url.path)",
                kind: .capture(url),
                title: date.formatted(date: .omitted, time: .shortened),
                date: date,
                icon: nil,
                preview: await thumbnail(for: url)))
        }

        // 4. 按时间排，最新的在最左边
        newItems.sort { $0.date > $1.date }
        items = newItems
    }

    // 给每个软件最大的那个窗口拍一张小预览图
    private func updateAppPreviews(for apps: [NSRunningApplication]) async {
        guard CGPreflightScreenCaptureAccess() else { return }   // 没给权限就只显示图标
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }

        for app in apps {
            let pid = app.processIdentifier
            let windows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
                    && $0.frame.width > 100 && $0.frame.height > 100
            }
            guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            else { continue }   // 最小化/隐藏的软件拍不到，就继续用上次拍到的

            let config = SCStreamConfiguration()
            config.width = 320
            config.height = Int(320 * window.frame.height / window.frame.width)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                appPreviews[pid] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    // 截图默认存在桌面；如果你在“截屏”App 里改过位置，就读那个位置
    private func captureFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private func latestCaptures(limit: Int) -> [(URL, Date)] {
        let prefixes = ["截屏", "录屏", "屏幕快照", "屏幕录制", "Screenshot", "Screen Shot", "Screen Recording"]
        let types = ["png", "jpg", "jpeg", "heic", "mov", "mp4"]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: captureFolder(), includingPropertiesForKeys: [.creationDateKey])) ?? []

        let captures = files.filter { url in
            types.contains(url.pathExtension.lowercased())
                && prefixes.contains { url.lastPathComponent.hasPrefix($0) }
        }
        let dated = captures.map { url in
            (url, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        return Array(dated.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    // 图片和视频都能用系统的 Quick Look 生成缩略图
    private func thumbnail(for url: URL) async -> NSImage? {
        if let cached = captureThumbs[url] { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 160, height: 100), scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        captureThumbs[url] = rep.nsImage
        return rep.nsImage
    }

    // 点一下：软件就切过去（最小化的窗口也会弹回来），截图/录屏就打开
    func open(_ item: LineItem) {
        switch item.kind {
        case .app(let app):
            if let url = app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .capture(let url):
            NSWorkspace.shared.open(url)
        }
    }

    // 删除截图/录屏：移到废纸篓（还能从废纸篓里拿回来）
    func trash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        captureThumbs[url] = nil
        items.removeAll { $0.fileURL == url }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
