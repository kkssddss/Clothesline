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
                                    Button("删除（移到废纸篓）", role: .destructive) { store.delete(item) }
                                }
                                .modifier(PullUpToDelete(item: item, store: store,
                                                         leaving: store.leaving.contains(item.id)))
                                .modifier(Sway(seed: item.seed))
                                // 按自己在屏幕上的位置，往下挪到绳子的高度
                                .visualEffect { content, proxy in
                                    content.offset(y: rope.y(at: proxy.frame(in: .global).midX) - rope.topY)
                                }
                                // 新挂上来的淡入；飞走的那张动画放完已经看不见了，直接拿掉
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                                                        removal: .identity))
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

// 按住图片可以随便拖，它会跟着鼠标走：
//   往上拉过 70 点再松手 → 删除（翻两圈、被风吹走）
//   没拉够就松手 → 弹回绳子上
//   往下拖 → 把文件拖到别的软件里（微信、Word……）
struct PullUpToDelete: ViewModifier {
    let item: LineItem
    let store: LineStore
    let leaving: Bool                           // 正在飞走
    @State private var pull: CGSize = .zero
    @State private var flight = 0.0             // 飞走动画走到哪了（0～1）
    @State private var draggingFile = false
    @GestureState private var pressing = false  // 手指还按着（拖动被打断时会自动变回 false）
    private let threshold: CGFloat = 70

    func body(content: Content) -> some View {
        let ready = pull.height < -threshold && !leaving
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
            .animation(.spring(duration: 0.2), value: ready)      // 只给垃圾桶和放大加动画，拖动本身不加
            .offset(pull)                                          // 跟着鼠标走
            .modifier(FloatAway(progress: flight))
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        guard !leaving, !draggingFile else { return }
                        let t = value.translation
                        // 明显往下拖：改成把文件拖出去
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
                            store.delete(item)                     // 从拉上去的位置开始飞走
                        } else {
                            springBack()
                        }
                    }
            )
            .allowsHitTesting(!leaving)
            .onChange(of: pressing) { _, isPressing in
                // 松手了（或拖动被打断）：没在飞走的话就弹回去
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

// 删除动画：上下翻两圈，然后被风轻轻带走，越飘越小（动作都收得比较小，不刺眼）
struct FloatAway: ViewModifier, Animatable {
    var progress: Double     // 0 = 好好挂着，1 = 已经飞走

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        // 前 45%：上下翻两圈（慢-快-慢），一边翻一边缩小，几乎不带透视，不会突然变大。
        // 翻完两圈后再多倒下去 78°，图片就平躺着，像一张纸被风托着
        let a = min(p / 0.45, 1)
        let flip = a * a * (3 - 2 * a)
        // 后 55%：平躺着被风轻轻带走，往右上方飘，越来越小、越来越淡，飘的时候微微起伏
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

// 风：几道白色的风线从左往右刮过去，末尾卷个小圈
struct WindStreaks: View {
    let progress: Double

    // 每道风线：高度、起点、终点（都按画布比例）、尾巴卷多大、什么时候开始、多粗
    private static let streaks: [(y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double)] = [
        (0.55, 0.05, 0.70, 9, 0.30, 1.4),
        (0.30, 0.15, 0.80, 7, 0.40, 1.2),
        (0.75, 0.10, 0.65, 0, 0.48, 1.0),
    ]

    var body: some View {
        Canvas { context, size in
            for streak in Self.streaks {
                let life = (progress - streak.delay) / 0.45          // 每道风线刮 45% 的时间
                guard life > 0, life < 1 else { continue }
                let path = Self.path(streak, in: size).trimmedPath(from: max(0, life - 0.4), to: life)
                context.stroke(path, with: .color(.white.opacity(0.45 * sin(life * .pi))),
                               style: StrokeStyle(lineWidth: streak.width, lineCap: .round))
            }
        }
        .frame(width: 260, height: 170)
        .shadow(color: .black.opacity(0.15), radius: 1)     // 淡淡的，浅色背景上也能隐约看到
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
