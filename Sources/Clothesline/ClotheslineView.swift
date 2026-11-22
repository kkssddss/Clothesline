import SwiftUI
import UniformTypeIdentifiers

struct ClotheslineView: View {
    @ObservedObject var store: LineStore

    var body: some View {
        GeometryReader { geo in
            let rope = Rope(width: geo.size.width)

            ZStack(alignment: .topLeading) {
                // 挂着的东西，太多就左右滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(store.items) { item in
                            HangingCard(item: item)
                                .onTapGesture { store.open(item) }
                                .onDrag { dragProvider(for: item) }
                                .contextMenu { menu(for: item) }
                                .modifier(Sway(seed: item.seed))
                                // 按自己在屏幕上的位置，往下挪到绳子的高度
                                .visualEffect { content, proxy in
                                    content.offset(y: rope.y(at: proxy.frame(in: .global).midX) - rope.topY)
                                }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, rope.topY - 6)          // 图片上沿比绳子高一点，像搭在绳子上
                    .padding(.bottom, rope.sag + 12)
                }

                // 绳子（画在图片前面）
                RopeShape(rope: rope)
                    .stroke(Color(red: 0.66, green: 0.52, blue: 0.38),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .overlay(
                        RopeShape(rope: rope)
                            .stroke(Color.white.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .allowsHitTesting(false)

                // 小动物
                AnimalsView(rope: rope)
            }
        }
        .animation(.spring(duration: 0.5), value: store.items.map(\.id))
    }

    // 右键菜单：截图/录屏多两个选项
    @ViewBuilder
    private func menu(for item: LineItem) -> some View {
        Button("打开") { store.open(item) }
        if let url = item.fileURL {
            Button("在访达中显示") { store.revealInFinder(url) }
            Divider()
            Button("删除（移到废纸篓）", role: .destructive) { store.trash(url) }
        }
    }

    // 截图/录屏可以直接拖进微信、Word 之类的地方
    private func dragProvider(for item: LineItem) -> NSItemProvider {
        if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) {
            return provider
        }
        return NSItemProvider()
    }
}

// 轻轻地来回晃，每张的幅度和快慢都不一样
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
                .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)   // 背景透明，加阴影才看得清
                .lineLimit(1)
                .frame(maxWidth: 140)
        }
    }

    // 没有外框，只有图片本身
    @ViewBuilder
    private var picture: some View {
        if let preview = item.preview {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 140, maxHeight: 88)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if item.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                }
                // 有窗口预览的软件，右下角放个小图标，好认
                .overlay(alignment: .bottomTrailing) {
                    if let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 24, height: 24).offset(x: 6, y: 6)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
        } else if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
    }
}
