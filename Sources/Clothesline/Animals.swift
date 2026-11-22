import SwiftUI
import Observation

// 在绳子上走来走去的小动物。
// 画法照着“脚本狗”里那只羊：纯代码画的圆和椭圆，逻辑尺寸 24×18、朝右；
// 走路只有两帧，四条腿一开一合，迈步那一帧整只往上提一点；偶尔停下来低头吃东西。

enum AnimalKind {
    case sheep, pig, cow, rooster
}

enum Pose {
    case walk0     // 腿并拢
    case walk1     // 腿分开（这一帧身子提起来一点）
    case nibble    // 停下来低头吃
}

// MARK: - 一群小动物（每 70 毫秒走一步）

@MainActor
@Observable
final class Herd {
    struct Member: Identifiable {
        let id: Int
        let kind: AnimalKind
        let scale: Double          // 1 个逻辑点 = 多少屏幕点（小羊羔就小一点）
        var x: Double
        var facing: Double         // 1 朝右，-1 朝左
        var nibble = 0             // 还要吃多少拍
        var step = 0               // 走了多少步
        var hopping = false        // 被点了，正在跳

        var pose: Pose { nibble > 0 ? .nibble : (step % 2 == 1 ? .walk1 : .walk0) }
        var bob: Double { pose == .walk1 ? -1 : 0 }
    }

    static let tick = 0.07                 // 一拍 70 毫秒
    static let stepTicks = 3               // 每 3 拍换一次腿
    static let speed = 16.0                // 每秒走 16 个逻辑点
    static let nibbleChance = 0.004        // 走路时每拍有 0.4% 的机会停下来吃
    static let nibbleTicks = 18...36       // 吃 1.3～2.5 秒

    var members: [Member] = []
    @ObservationIgnored var width: Double = 0
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var timer: Timer?

    func start(width: Double) {
        self.width = width
        guard timer == nil else { return }
        // 两只羊（一只是小羊羔）、一只猪、一头牛、一只大公鸡
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
                    // 走到头：转身，顺便吃一会
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

    // 点一下跳一下
    func hop(_ id: Int) {
        guard let i = members.firstIndex(where: { $0.id == id }), !members[i].hopping else { return }
        members[i].hopping = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if let self, let i = self.members.firstIndex(where: { $0.id == id }) {
                self.members[i].hopping = false
            }
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
                let feet = (17.2 - 9) * m.scale        // 脚底离画布中心多远
                AnimalSprite(kind: m.kind, pose: m.pose, scale: m.scale)
                    .onTapGesture { herd.hop(m.id) }
                    .allowsHitTesting(m.kind != .rooster)   // 公鸡点不了
                    .scaleEffect(x: m.facing, y: 1)     // 画的时候朝右，往左走就镜像
                    .rotationEffect(.radians(rope.angle(at: x)), anchor: UnitPoint(x: 0.5, y: 17.2 / 18))
                    .shadow(color: .black.opacity(0.3), radius: 1.2, y: 1)
                    .offset(y: m.hopping ? -24 : 0)
                    .animation(m.hopping ? .easeOut(duration: 0.2) : .easeIn(duration: 0.2), value: m.hopping)
                    .position(x: x, y: rope.y(at: x) - feet + 1 + m.bob)
                    .animation(.linear(duration: Herd.tick), value: m.x)   // 两拍之间平滑地走
            }
        }
        .onAppear { herd.start(width: Double(rope.width)) }
        .onChange(of: rope.width) { _, width in herd.width = Double(width) }
    }
}

// MARK: - 画一只小动物

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

// 所有坐标都是逻辑坐标（24×18，左上角是原点，朝右），画的时候乘以 u
struct AnimalPainter {
    let u: CGFloat
    let pose: Pose

    static let wool = hex(0xfbfaf4), woolEdge = hex(0xa7aab2), face = hex(0x4b4f59)
    static let blush = hex(0xff9fb0), pupil = hex(0x111111)

    // 腿往里并（1）、往外分（-1）、并齐吃东西（0）
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

    // MARK: 羊（和脚本狗那只一模一样）

    private func sheep(_ ctx: GraphicsContext) {
        fourLegs(ctx, color: Self.face, width: 1.7, top: 11.5)
        let puffs: [(CGFloat, CGFloat)] = [(6.5, 7.2), (9.8, 5.6), (13.4, 5.8), (16.0, 7.6), (15.2, 10.6),
                                           (11.0, 11.4), (7.0, 10.6), (4.6, 9.0), (10.8, 8.4)]
        // 先用灰色把 9 个圆各放大一点画一遍，再用羊毛色盖上去 → 只剩外面一圈灰边
        for (cx, cy) in puffs { fill(ctx, oval(cx - 3.8, cy - 3.8, cx + 3.8, cy + 3.8), Self.woolEdge) }
        for (cx, cy) in puffs { fill(ctx, oval(cx - 3.3, cy - 3.3, cx + 3.3, cy + 3.3), Self.wool) }
        let headY: CGFloat = nibbling ? 9.4 : 5.4
        fill(ctx, oval(17.4, headY, 23.2, headY + 5.6), Self.face)              // 头
        fill(ctx, oval(17.0, headY + 0.4, 19.2, headY + 2.0), Self.face)        // 耳朵
        eye(ctx, 20.9, headY + 2.0)
        fill(ctx, oval(21.0, headY + 3.6, 22.4, headY + 4.4), Self.blush)       // 腮红
    }

    // MARK: 小猪

    private func pig(_ ctx: GraphicsContext) {
        let pink = Self.hex(0xffc8d2), edge = Self.hex(0xe48ea3), leg = Self.hex(0xf4a9b8)
        let snout = Self.hex(0xf7a3b4), nostril = Self.hex(0xc0647a)
        fourLegs(ctx, color: leg, width: 1.9, top: 10.8)
        ctx.stroke(oval(1.9, 6.0, 3.9, 8.0), with: .color(edge), lineWidth: 0.55 * u)  // 卷卷的小尾巴
        fill(ctx, oval(3.0, 4.0, 18.0, 13.7), edge)
        fill(ctx, oval(3.5, 4.5, 17.5, 13.2), pink)                              // 身体
        let headY: CGFloat = nibbling ? 7.6 : 4.4
        fill(ctx, triangle((16.4, headY + 1.4), (17.2, headY - 1.4), (18.6, headY + 0.8)), leg)  // 后面的耳朵
        fill(ctx, oval(15.3, headY - 0.5, 22.7, headY + 6.5), edge)
        fill(ctx, oval(15.8, headY, 22.2, headY + 6.0), pink)                    // 头
        fill(ctx, triangle((17.8, headY + 1.0), (19.0, headY - 1.6), (20.2, headY + 0.8)), leg)  // 前面的耳朵
        fill(ctx, oval(20.9, headY + 2.2, 23.8, headY + 4.6), snout)             // 鼻子
        fill(ctx, oval(21.6, headY + 3.0, 22.2, headY + 3.8), nostril)
        fill(ctx, oval(22.6, headY + 3.0, 23.2, headY + 3.8), nostril)
        eye(ctx, 19.4, headY + 2.0)
        fill(ctx, oval(17.8, headY + 3.8, 19.2, headY + 4.6), Self.blush)
    }

    // MARK: 奶牛

    private func cow(_ ctx: GraphicsContext) {
        let white = Self.wool, edge = Self.woolEdge, spot = Self.face
        let muzzle = Self.hex(0xffc9cf), nostril = Self.hex(0xc0647a), horn = Self.hex(0xf3e2b3)
        fourLegs(ctx, color: white, width: 1.8, top: 10.5, edge: edge, hoof: spot)
        var tail = Path()                                                        // 尾巴
        tail.move(to: pt(3.4, 6.2))
        tail.addQuadCurve(to: pt(2.2, 10.6), control: pt(1.8, 7.0))
        ctx.stroke(tail, with: .color(spot), style: StrokeStyle(lineWidth: 0.5 * u, lineCap: .round))
        fill(ctx, oval(1.5, 10.0, 2.9, 11.9), spot)
        fill(ctx, rounded(2.5, 4.1, 18.1, 13.1, 3.7), edge)
        let torso = rounded(3.0, 4.6, 17.6, 12.6, 3.2)
        fill(ctx, torso, white)                                                  // 身体
        var spots = ctx                                                          // 黑色花斑
        spots.clip(to: torso)
        fill(spots, oval(4.8, 5.0, 9.4, 8.8), spot)
        fill(spots, oval(10.6, 8.6, 15.0, 13.0), spot)
        fill(spots, oval(14.2, 3.8, 17.8, 7.0), spot)
        let headY: CGFloat = nibbling ? 7.6 : 3.6
        fill(ctx, oval(17.6, headY - 1.3, 18.8, headY + 0.6), horn)              // 小角
        fill(ctx, oval(20.4, headY - 1.3, 21.6, headY + 0.6), horn)
        fill(ctx, oval(15.4, headY + 0.6, 18.2, headY + 2.4), edge)
        fill(ctx, oval(15.7, headY + 0.9, 17.9, headY + 2.1), white)             // 耳朵
        fill(ctx, oval(16.3, headY - 0.5, 22.9, headY + 6.3), edge)
        let head = oval(16.8, headY, 22.4, headY + 5.8)
        fill(ctx, head, white)                                                   // 头
        var patch = ctx
        patch.clip(to: head)
        fill(patch, oval(16.0, headY - 1.0, 20.2, headY + 2.8), spot)           // 眼睛那块黑斑
        fill(ctx, oval(19.4, headY + 3.1, 23.8, headY + 6.2), muzzle)            // 粉色的嘴
        fill(ctx, oval(20.6, headY + 4.2, 21.2, headY + 5.0), nostril)
        fill(ctx, oval(22.0, headY + 4.2, 22.6, headY + 5.0), nostril)
        eye(ctx, 19.9, headY + 2.0)
    }

    // MARK: 大公鸡

    private func rooster(_ ctx: GraphicsContext) {
        let body = Self.hex(0xd9774a), edge = Self.hex(0xa9502c), wing = Self.hex(0xb85c34)
        let neck = Self.hex(0xf0a45a), neckEdge = Self.hex(0xc9783a)
        let red = Self.hex(0xe63946), yellow = Self.hex(0xf2b134)
        let feathers = [Self.hex(0x1f3d45), Self.hex(0x2f5d62), Self.hex(0x3e7a6e)]
        // 两条黄色的腿，也是一开一合，带三个脚趾
        for (index, lx) in [9.4, 11.8].enumerated() {
            let x0 = CGFloat(lx) + (index == 0 ? legShift : -legShift) * 0.6
            fill(ctx, rounded(x0, 12.6, x0 + 0.9, 17.2, 0.45), yellow)
            fill(ctx, rounded(x0 - 0.5, 16.5, x0 + 2.2, 17.2, 0.35), yellow)
        }
        // 翘起来的大尾巴（三根深绿色羽毛）
        fill(ctx, oval(1.0, 3.6, 8.6, 6.0, rotation: -0.95, around: (5.6, 7.6)), feathers[0])
        fill(ctx, oval(0.8, 6.0, 8.0, 8.4, rotation: -0.55, around: (5.6, 8.6)), feathers[1])
        fill(ctx, oval(1.2, 8.6, 7.8, 10.8, rotation: -0.15, around: (5.8, 9.6)), feathers[2])
        // 身体和翅膀
        fill(ctx, oval(5.3, 6.1, 16.5, 14.9), edge)
        fill(ctx, oval(5.8, 6.6, 16.0, 14.4), body)
        fill(ctx, oval(7.2, 9.0, 12.8, 12.6), wing)
        // 脖子和头（吃东西时低下去）
        let dy: CGFloat = nibbling ? 3.0 : 0
        fill(ctx, oval(12.5, 4.3 + dy, 18.1, 11.5), neckEdge)
        fill(ctx, oval(13.0, 4.8 + dy, 17.6, 11.0), neck)
        fill(ctx, oval(13.1, 2.5 + dy, 18.9, 8.1 + dy), neckEdge)
        fill(ctx, oval(13.6, 3.0 + dy, 18.4, 7.6 + dy), neck)
        // 红色的鸡冠、肉垂，黄色的嘴
        fill(ctx, oval(14.0, 1.6 + dy, 15.8, 3.4 + dy), red)
        fill(ctx, oval(15.1, 1.0 + dy, 17.1, 3.0 + dy), red)
        fill(ctx, oval(16.4, 1.6 + dy, 18.0, 3.4 + dy), red)
        fill(ctx, triangle((18.2, 4.6 + dy), (20.4, 5.5 + dy), (18.2, 6.4 + dy)), yellow)
        fill(ctx, oval(17.4, 6.0 + dy, 18.8, 8.4 + dy), red)
        eye(ctx, 16.7, 4.8 + dy)
    }

    // MARK: 画图小工具

    // 四条竖着的腿，两两一组，一组往里并、另一组往外分
    private func fourLegs(_ ctx: GraphicsContext, color: Color, width: CGFloat, top: CGFloat,
                          edge: Color? = nil, hoof: Color? = nil) {
        for (index, lx) in [6.0, 9.0, 13.5, 16.5].enumerated() {
            let x0 = CGFloat(lx) + (index % 2 == 0 ? legShift : -legShift) * 0.6
            if let edge { fill(ctx, rounded(x0 - 0.4, top, x0 + width + 0.4, 17.6, 1.0), edge) }
            fill(ctx, rounded(x0, top, x0 + width, 17.2, 0.8), color)
            if let hoof { fill(ctx, rounded(x0, 16.0, x0 + width, 17.2, 0.6), hoof) }
        }
    }

    // 眼白 + 稍微偏右下的瞳孔，像在看前面
    private func eye(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        fill(ctx, oval(x - 0.9, y - 0.9, x + 0.9, y + 0.9), .white)
        fill(ctx, oval(x - 0.35, y - 0.35, x + 0.45, y + 0.45), Self.pupil)
    }

    private func fill(_ ctx: GraphicsContext, _ path: Path, _ color: Color) {
        ctx.fill(path, with: .color(color))
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

    // 用左上角、右下角来画椭圆（和 Pillow 一样）
    private func oval(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x0 * u, y: y0 * u, width: (x1 - x0) * u, height: (y1 - y0) * u))
    }

    // 同上，再绕着某个点转一个角度（公鸡尾巴的羽毛用）
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
