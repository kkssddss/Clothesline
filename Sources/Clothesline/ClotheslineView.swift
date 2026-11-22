import SwiftUI
import UniformTypeIdentifiers

struct ClotheslineView: View {
    @ObservedObject var store: LineStore
    var topInset: CGFloat = 0          // 窗口最上面被菜单栏占掉的高度

    var body: some View {
        GeometryReader { geo in
            let rope = Rope(width: geo.size.width, topY: topInset + 44)

            ZStack(alignment: .topLeading) {
                // 挂着的截图和录屏，太多就左右滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(store.items) { item in
                            HangingCard(item: item)
                                .onTapGesture { store.open(item) }
                                .contextMenu {
                                    Button("打开") { store.open(item) }
                                    Button("在访达中显示") { store.revealInFinder(item) }
                                    Divider()
                                    Button("删除（移到废纸篓）", role: .destructive) { store.trash(item) }
                                }
                                .modifier(PullUpToDelete(item: item, store: store))
                                .modifier(Sway(seed: item.seed))
                                // 按自己在屏幕上的位置，往下挪到绳子的高度
                                .visualEffect { content, proxy in
                                    content.offset(y: rope.y(at: proxy.frame(in: .global).midX) - rope.topY)
                                }
                                .transition(.floatAway)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, rope.topY - 6)          // 图片上沿比绳子高一点，像搭在绳子上
                    .padding(.bottom, rope.sag + 12)
                }
                .scrollClipDisabled()                      // 飞走的图片可以飞出滚动区域

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

// 拖着图片往上拉，拉过一定高度松手就删除；往别的方向拖，就是把文件拖到别的软件里
struct PullUpToDelete: ViewModifier {
    let item: LineItem
    let store: LineStore
    @State private var pull: CGSize = .zero
    @State private var mode: Mode = .none
    private let threshold: CGFloat = 70        // 往上拉超过 70 点，松手就删

    enum Mode { case none, pulling, draggingFile }

    func body(content: Content) -> some View {
        let ready = pull.height < -threshold
        content
            .overlay(alignment: .top) {
                if ready {
                    // 拉够了：出现一个小垃圾桶，提示松手就删
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
            .offset(x: pull.width * 0.3, y: min(pull.height, 0))
            .animation(.spring(duration: 0.25), value: ready)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        let t = value.translation
                        if hypot(t.width, t.height) < 8 { mode = .none }     // 新的一次拖动
                        if mode == .none {
                            if t.height < 0 && abs(t.height) > abs(t.width) {
                                mode = .pulling
                            } else if hypot(t.width, t.height) >= 6 {
                                mode = .draggingFile
                                store.beginFileDrag(item)
                            }
                        }
                        if mode == .pulling { pull = t }
                    }
                    .onEnded { value in
                        if mode == .pulling && value.translation.height < -threshold {
                            store.trash(item)          // 留在拉上去的位置，从那里开始飞走
                        } else {
                            withAnimation(.spring(duration: 0.45, bounce: 0.45)) { pull = .zero }
                        }
                        mode = .none
                    }
            )
    }
}

// 删除动画：上下翻两圈，然后被风带着，从大变小飞向远方
struct FloatAway: ViewModifier, Animatable {
    var progress: Double     // 0 = 好好挂着，1 = 已经飞走

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        // 前 30%：上下翻两圈（慢-快-慢），顺便往上飘一点
        let a = min(p / 0.3, 1)
        let flip = a * a * (3 - 2 * a)
        // 后 70%：先被风托起来变大一点，然后越飞越远、越来越小
        let b = max(0, (p - 0.3) / 0.7)
        let scale = b < 0.15 ? 1 + b : max(0.03, 1.15 * pow(1 - (b - 0.15) / 0.85, 1.5))
        let x = 170 * pow(b, 1.2) + sin(b * 3 * .pi) * 22
        let y = -16 * flip - 190 * pow(b, 1.1)
        content
            .rotation3DEffect(.degrees(720 * flip), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotationEffect(.degrees(sin(b * 2.5 * .pi) * 14))
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .opacity(b < 0.75 ? 1 : 1 - (b - 0.75) / 0.25)
            .overlay {
                if p > 0 { WindStreaks(progress: p).offset(y: -40) }
            }
    }
}

extension AnyTransition {
    static var floatAway: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
            removal: .modifier(active: FloatAway(progress: 1), identity: FloatAway(progress: 0))
                .animation(.linear(duration: LineStore.deleteDuration)))
    }
}

// 风：几道白色的风线从左往右刮过去，末尾卷个小圈
struct WindStreaks: View {
    let progress: Double

    // 每道风线：高度、起点、终点（都按画布比例）、尾巴卷多大、什么时候开始、多粗
    private static let streaks: [(y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double)] = [
        (0.55, 0.00, 0.72, 14, 0.18, 3.0),
        (0.35, 0.10, 0.82, 10, 0.26, 2.4),
        (0.74, 0.05, 0.68, 0, 0.32, 2.0),
        (0.20, 0.22, 0.88, 8, 0.40, 1.8),
        (0.62, 0.30, 0.95, 11, 0.46, 2.2),
    ]

    var body: some View {
        Canvas { context, size in
            for streak in Self.streaks {
                let life = (progress - streak.delay) / 0.45          // 每道风线刮 45% 的时间
                guard life > 0, life < 1 else { continue }
                let path = Self.path(streak, in: size).trimmedPath(from: max(0, life - 0.4), to: life)
                context.stroke(path, with: .color(.white.opacity(0.9 * sin(life * .pi))),
                               style: StrokeStyle(lineWidth: streak.width, lineCap: .round))
            }
        }
        .frame(width: 340, height: 240)
        .shadow(color: .black.opacity(0.35), radius: 1.5)   // 浅色背景上也看得见
        .allowsHitTesting(false)
    }

    private static func path(_ s: (y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double),
                             in size: CGSize) -> Path {
        let y = s.y * size.height
        let x0 = s.from * size.width, x1 = s.to * size.width
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y))
        // 波浪形往右刮
        path.addCurve(to: CGPoint(x: x1, y: y - 12),
                      control1: CGPoint(x: x0 + (x1 - x0) * 0.35, y: y - 16),
                      control2: CGPoint(x: x0 + (x1 - x0) * 0.65, y: y + 10))
        // 末尾卷一个小圈
        if s.curl > 0 {
            path.addArc(center: CGPoint(x: x1, y: y - 12 - s.curl), radius: s.curl,
                        startAngle: .degrees(90), endAngle: .degrees(-200), clockwise: true)
        }
        return path
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
