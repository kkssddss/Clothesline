import SwiftUI
import UniformTypeIdentifiers

struct ClotheslineView: View {
    @ObservedObject var store: LineStore

    var body: some View {
        GeometryReader { geo in
            let rope = Rope(width: geo.size.width)

            ZStack(alignment: .topLeading) {
                // 挂着的截图和录屏，太多就左右滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(store.items) { item in
                            HangingCard(item: item)
                                .onTapGesture { store.open(item) }
                                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                                .contextMenu {
                                    Button("打开") { store.open(item) }
                                    Button("在访达中显示") { store.revealInFinder(item) }
                                    Divider()
                                    Button("删除（移到废纸篓）", role: .destructive) { store.trash(item) }
                                }
                                .modifier(Sway(seed: item.seed))
                                // 按自己在屏幕上的位置，往下挪到绳子的高度
                                .visualEffect { content, proxy in
                                    content.offset(y: rope.y(at: proxy.frame(in: .global).midX) - rope.topY)
                                }
                                .transition(.blownAway)
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
}

// 删除时：先被风吹得抖几下，然后翻着跟头飞走
struct BlownAway: ViewModifier, Animatable {
    var progress: Double     // 0 = 好好挂着，1 = 已经飞走

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        // 前 20%：风来了，抖几下
        let shake = p < 0.2 ? sin(p / 0.2 * 4 * .pi) * 9 : 0
        // 后 80%：被吹走，越飞越快、上下飘、翻转、变小、变淡
        let q = max(0, (p - 0.2) / 0.8)
        content
            .rotation3DEffect(.degrees(sin(q * 3 * .pi) * 55), axis: (x: 0, y: 1, z: 0.2), anchor: .top)
            .rotationEffect(.degrees(shake + q * 40 + sin(q * 4 * .pi) * 12), anchor: .top)
            .scaleEffect(1 - q * 0.35, anchor: .top)
            .offset(x: q * q * 380, y: -q * 50 + sin(q * 3 * .pi) * 14)
            .opacity(1 - pow(q, 1.6))
    }
}

extension AnyTransition {
    static var blownAway: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
            removal: .modifier(active: BlownAway(progress: 1), identity: BlownAway(progress: 0)))
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
                // 原来只在剪贴板里的截图，右下角放个小标记
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
