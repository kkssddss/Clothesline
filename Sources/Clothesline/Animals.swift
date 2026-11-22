import SwiftUI

// 在绳子上走来走去的小动物（用代码画的，走路时腿一前一后分开迈）
enum AnimalKind: CaseIterable {
    case sheep, brownSheep, pig, cow, chick

    // 走一个完整的步子（两对腿各迈一次）往前走多远
    var stride: Double {
        switch self {
        case .chick: return 8
        case .pig: return 12
        case .cow: return 18
        case .sheep, .brownSheep: return 15
        }
    }
}

struct WalkingAnimal: Identifiable {
    let id: Int
    let kind: AnimalKind
    let speed: Double      // 每秒走多少点
    let start: Double      // 起点错开，大家不挤在一起
}

struct AnimalsView: View {
    let rope: Rope
    @State private var animals = AnimalsView.makeAnimals()
    @State private var hopStarts: [Int: Date] = [:]

    static func makeAnimals() -> [WalkingAnimal] {
        AnimalKind.allCases.shuffled().enumerated().map { index, kind in
            WalkingAnimal(id: index, kind: kind,
                          speed: kind == .chick ? .random(in: 12...20) : .random(in: 16...30),
                          start: .random(in: 0...5000))
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(animals) { animal in
                    let distance = animal.start + t * animal.speed
                    let (x, facingRight) = walk(distance)
                    AnimalSprite(kind: animal.kind, phase: distance / animal.kind.stride * 2 * .pi)
                        .onTapGesture { hopStarts[animal.id] = Date() }   // 点一下跳一下
                        .scaleEffect(x: facingRight ? 1 : -1, y: 1)        // 画的时候朝右，往左走就翻过来
                        .rotationEffect(.radians(rope.angle(at: x)), anchor: UnitPoint(x: 0.5, y: 0.88))
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .position(x: x, y: rope.y(at: x) - 15 - hop(animal.id, now: timeline.date))
                }
            }
        }
    }

    // 在绳子上从一头走到另一头，再走回来
    private func walk(_ distance: Double) -> (CGFloat, Bool) {
        let margin: Double = 30
        let length = max(Double(rope.width) - margin * 2, 1)
        let d = distance.truncatingRemainder(dividingBy: length * 2)
        return d < length ? (CGFloat(margin + d), true) : (CGFloat(margin + length * 2 - d), false)
    }

    private func hop(_ id: Int, now: Date) -> CGFloat {
        guard let start = hopStarts[id] else { return 0 }
        let p = now.timeIntervalSince(start) / 0.5     // 跳一下 0.5 秒
        guard p < 1 else { return 0 }
        return CGFloat(4 * 28 * p * (1 - p))           // 最高跳 28 点
    }
}

// 一只小动物（46×38 的小画布，脚踩在 y≈33 的地方）
struct AnimalSprite: View {
    let kind: AnimalKind
    let phase: Double      // 走路走到哪一拍了

    var body: some View {
        Canvas { context, _ in
            AnimalPainter(phase: phase).draw(kind, in: context)
        }
        .frame(width: 46, height: 38)
    }
}

struct AnimalPainter {
    let phase: Double
    let maxSwing = 0.45                                // 腿最多摆多少（弧度，约 26°）
    var swing: Double { sin(phase) * maxSwing }
    var nod: Double { sin(phase * 2) * 0.05 }          // 走路时头一点一点
    static let blush = Color(red: 1, green: 0.45, blue: 0.55).opacity(0.5)

    func draw(_ kind: AnimalKind, in ctx: GraphicsContext) {
        switch kind {
        case .sheep:
            sheep(ctx, wool: rgb(0.99, 0.98, 0.95), woolLine: rgb(0.74, 0.71, 0.66),
                  face: rgb(0.36, 0.31, 0.29), faceLine: rgb(0.22, 0.19, 0.18), darkFace: true,
                  leg: rgb(0.33, 0.29, 0.27), farLeg: rgb(0.24, 0.21, 0.2), hoof: nil)
        case .brownSheep:
            sheep(ctx, wool: rgb(0.93, 0.81, 0.65), woolLine: rgb(0.7, 0.56, 0.4),
                  face: rgb(0.99, 0.94, 0.88), faceLine: rgb(0.72, 0.6, 0.48), darkFace: false,
                  leg: rgb(0.97, 0.91, 0.84), farLeg: rgb(0.86, 0.78, 0.7), hoof: rgb(0.5, 0.38, 0.3))
        case .pig: pig(ctx)
        case .cow: cow(ctx)
        case .chick: chick(ctx)
        }
    }

    // MARK: 羊

    private func sheep(_ ctx: GraphicsContext, wool: Color, woolLine: Color, face: Color, faceLine: Color,
                       darkFace: Bool, leg legColor: Color, farLeg: Color, hoof: Color?) {
        let length: CGFloat = 9, hipY: CGFloat = 25
        let up = lift(length, swing, maxSwing)
        // 四条腿：对角的两条一起迈（远处的颜色深一点，先画）
        leg(ctx, hip: CGPoint(x: 17, y: hipY - up), angle: -swing, length: length, width: 3.6, color: farLeg, hoof: hoof)
        leg(ctx, hip: CGPoint(x: 31, y: hipY - up), angle: swing, length: length, width: 3.6, color: farLeg, hoof: hoof)
        leg(ctx, hip: CGPoint(x: 14, y: hipY - up), angle: swing, length: length, width: 3.6, color: legColor, hoof: hoof)
        leg(ctx, hip: CGPoint(x: 28, y: hipY - up), angle: -swing, length: length, width: 3.6, color: legColor, hoof: hoof)

        let body = raised(ctx, by: up)
        fluff(body, [(8.5, 17, 3.6)], fill: wool, line: woolLine)                       // 小尾巴
        fluff(body, [(15, 13, 7), (23, 11, 7.5), (30, 13.5, 6.5), (12.5, 20, 6.5),
                     (20, 22, 7), (28, 21, 6.5), (22, 17, 9)], fill: wool, line: woolLine)  // 毛茸茸的身体

        let head = nodding(body, around: CGPoint(x: 33, y: 18))
        outlined(head, oval(32.5, 14.5, 7.5, 3.8, rotation: -0.4), fill: face, line: faceLine, width: 1.6)  // 耳朵
        outlined(head, oval(37, 17.3, 11, 12.5), fill: face, line: faceLine, width: 1.6)                    // 脸
        fluff(head, [(34.6, 11.2, 3.6), (38.2, 10.8, 3.2)], fill: wool, line: woolLine)                    // 头顶一撮毛
        eye(head, 38.8, 16.6, onDark: darkFace)
        cheek(head, 40, 20.2)
    }

    // MARK: 小猪

    private func pig(_ ctx: GraphicsContext) {
        let pink = rgb(1.0, 0.77, 0.81), line = rgb(0.86, 0.5, 0.58)
        let near = rgb(0.97, 0.68, 0.74), far = rgb(0.88, 0.57, 0.64)
        let length: CGFloat = 7, hipY: CGFloat = 26.5
        let up = lift(length, swing, maxSwing)
        leg(ctx, hip: CGPoint(x: 18, y: hipY - up), angle: -swing, length: length, width: 4.2, color: far)
        leg(ctx, hip: CGPoint(x: 31, y: hipY - up), angle: swing, length: length, width: 4.2, color: far)
        leg(ctx, hip: CGPoint(x: 15, y: hipY - up), angle: swing, length: length, width: 4.2, color: near)
        leg(ctx, hip: CGPoint(x: 28, y: hipY - up), angle: -swing, length: length, width: 4.2, color: near)

        let body = raised(ctx, by: up)
        var tail = Path()                                                               // 卷卷的尾巴
        tail.move(to: CGPoint(x: 9.5, y: 17))
        tail.addCurve(to: CGPoint(x: 5, y: 14.5), control1: CGPoint(x: 7, y: 19.5), control2: CGPoint(x: 4, y: 17.5))
        tail.addCurve(to: CGPoint(x: 7.8, y: 12.5), control1: CGPoint(x: 5.6, y: 11.8), control2: CGPoint(x: 7.4, y: 11.6))
        body.stroke(tail, with: .color(line), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        outlined(body, Path(ellipseIn: CGRect(x: 8, y: 10, width: 29, height: 19)), fill: pink, line: line)

        let head = nodding(body, around: CGPoint(x: 33, y: 19))
        let ear = rgb(0.96, 0.62, 0.7)
        head.fill(triangle((30.5, 10), (33.5, 5.5), (35.5, 10.5)), with: .color(ear))              // 后面的耳朵
        outlined(head, circle(36, 17, 8), fill: pink, line: line)                                   // 头
        outlined(head, triangle((35, 10), (39.5, 5.8), (40.3, 11)), fill: ear, line: line, width: 1.2)  // 前面的耳朵
        outlined(head, oval(42.2, 19, 6, 5.4), fill: rgb(1.0, 0.64, 0.72), line: line, width: 1.2)  // 鼻子
        head.fill(oval(41.4, 19, 1.1, 1.6), with: .color(rgb(0.72, 0.36, 0.46)))
        head.fill(oval(43.1, 19, 1.1, 1.6), with: .color(rgb(0.72, 0.36, 0.46)))
        eye(head, 37.6, 15.2, onDark: false)
        cheek(head, 36, 20.3)
    }

    // MARK: 奶牛

    private func cow(_ ctx: GraphicsContext) {
        let white = rgb(0.99, 0.99, 0.97), line = rgb(0.6, 0.58, 0.56), spot = rgb(0.2, 0.19, 0.19)
        let far = rgb(0.86, 0.85, 0.83), hoof = rgb(0.28, 0.26, 0.26)
        let length: CGFloat = 10, hipY: CGFloat = 23.5
        let up = lift(length, swing, maxSwing)
        leg(ctx, hip: CGPoint(x: 16, y: hipY - up), angle: -swing, length: length, width: 4, color: far, hoof: hoof)
        leg(ctx, hip: CGPoint(x: 30, y: hipY - up), angle: swing, length: length, width: 4, color: far, hoof: hoof)
        leg(ctx, hip: CGPoint(x: 13, y: hipY - up), angle: swing, length: length, width: 4, color: white, hoof: hoof)
        leg(ctx, hip: CGPoint(x: 27, y: hipY - up), angle: -swing, length: length, width: 4, color: white, hoof: hoof)

        let body = raised(ctx, by: up)
        var tail = Path()
        tail.move(to: CGPoint(x: 8.5, y: 13))
        tail.addQuadCurve(to: CGPoint(x: 5.5, y: 22), control: CGPoint(x: 4.5, y: 14))
        body.stroke(tail, with: .color(spot), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        body.fill(oval(5.5, 23, 3, 4), with: .color(spot))
        let torso = Path(roundedRect: CGRect(x: 7, y: 9, width: 29, height: 17), cornerRadius: 8)
        outlined(body, torso, fill: white, line: line)
        var spots = body                                                                // 黑色花斑
        spots.clip(to: torso)
        spots.fill(oval(14, 13, 9, 7, rotation: 0.3), with: .color(spot))
        spots.fill(oval(25, 20, 10, 7, rotation: -0.2), with: .color(spot))
        spots.fill(oval(31, 11, 6, 4.5), with: .color(spot))

        let head = nodding(body, around: CGPoint(x: 33, y: 15))
        let horn = rgb(0.98, 0.91, 0.72), hornLine = rgb(0.75, 0.66, 0.45)
        outlined(head, oval(34.8, 6.8, 2.6, 4.2, rotation: -0.3), fill: horn, line: hornLine, width: 1)  // 小角
        outlined(head, oval(39.6, 6.8, 2.6, 4.2, rotation: 0.3), fill: horn, line: hornLine, width: 1)
        outlined(head, oval(31.2, 11.5, 7, 3.6, rotation: -0.35), fill: white, line: line, width: 1.4)  // 耳朵
        let face = Path(ellipseIn: CGRect(x: 32, y: 6.5, width: 12, height: 14))
        outlined(head, face, fill: white, line: line, width: 1.6)
        var patch = head
        patch.clip(to: face)
        patch.fill(oval(36, 9, 7, 6.5), with: .color(spot))                            // 眼睛那块黑斑
        outlined(head, oval(39.8, 18.6, 10.5, 7.2), fill: rgb(1.0, 0.79, 0.81),
                 line: rgb(0.85, 0.55, 0.6), width: 1.2)                                // 粉色的嘴
        head.fill(oval(38, 18.6, 1.3, 1.8), with: .color(rgb(0.7, 0.38, 0.44)))
        head.fill(oval(41.6, 18.6, 1.3, 1.8), with: .color(rgb(0.7, 0.38, 0.44)))
        eye(head, 38.6, 12, onDark: true)
    }

    // MARK: 小鸡

    private func chick(_ ctx: GraphicsContext) {
        let yellow = rgb(1.0, 0.87, 0.34), line = rgb(0.92, 0.66, 0.16)
        let orange = rgb(1.0, 0.56, 0.16), darkOrange = rgb(0.92, 0.48, 0.12)
        let s = sin(phase) * 0.5
        let length: CGFloat = 6, hipY: CGFloat = 27.5
        let up = lift(length, s, 0.5)
        leg(ctx, hip: CGPoint(x: 23.5, y: hipY - up), angle: -s, length: length, width: 1.8, color: darkOrange, foot: darkOrange)
        leg(ctx, hip: CGPoint(x: 20, y: hipY - up), angle: s, length: length, width: 1.8, color: orange, foot: orange)

        let body = raised(ctx, by: up)
        var tuft = Path()                                                               // 头顶两根呆毛
        tuft.move(to: CGPoint(x: 21, y: 11))
        tuft.addQuadCurve(to: CGPoint(x: 19.6, y: 7), control: CGPoint(x: 19.2, y: 9.6))
        tuft.move(to: CGPoint(x: 22.6, y: 10.8))
        tuft.addQuadCurve(to: CGPoint(x: 24.4, y: 7.2), control: CGPoint(x: 24.2, y: 9.6))
        body.stroke(tuft, with: .color(line), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        outlined(body, circle(22, 20, 9.5), fill: yellow, line: line)
        outlined(body, oval(17.5, 21, 9, 6, rotation: -0.35 + sin(phase * 2) * 0.18),
                 fill: rgb(1.0, 0.8, 0.26), line: line, width: 1.2)                    // 小翅膀扇一扇
        body.fill(triangle((30.6, 18), (34.8, 19.8), (30.6, 21.6)), with: .color(orange))  // 嘴
        eye(body, 27, 17.2, onDark: false)
        cheek(body, 26.6, 21.4)
    }

    // MARK: 画图小工具

    // 腿越斜，身体就越低一点，这样脚一直踩在绳子上
    private func lift(_ length: CGFloat, _ angle: Double, _ maxAngle: Double) -> CGFloat {
        length * CGFloat(cos(angle) - cos(maxAngle))
    }

    private func leg(_ ctx: GraphicsContext, hip: CGPoint, angle: Double, length: CGFloat, width: CGFloat,
                     color: Color, hoof: Color? = nil, foot: Color? = nil) {
        var c = ctx
        c.translateBy(x: hip.x, y: hip.y)
        c.rotate(by: .radians(angle))
        c.fill(Path(roundedRect: CGRect(x: -width / 2, y: -1, width: width, height: length + 1), cornerRadius: width / 2),
               with: .color(color))
        if let hoof {
            c.fill(Path(roundedRect: CGRect(x: -width / 2, y: length - 2.4, width: width, height: 2.4), cornerRadius: 1),
                   with: .color(hoof))
        }
        if let foot {
            c.fill(Path(roundedRect: CGRect(x: -1, y: length - 1.2, width: 4.2, height: 1.6), cornerRadius: 0.8),
                   with: .color(foot))
        }
    }

    private func raised(_ ctx: GraphicsContext, by up: CGFloat) -> GraphicsContext {
        var c = ctx
        c.translateBy(x: 0, y: -up)
        return c
    }

    private func nodding(_ ctx: GraphicsContext, around p: CGPoint) -> GraphicsContext {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(nod))
        c.translateBy(x: -p.x, y: -p.y)
        return c
    }

    // 先描一圈粗边、再填色，最后只露出外面一圈轮廓
    private func outlined(_ ctx: GraphicsContext, _ path: Path, fill: Color, line: Color, width: CGFloat = 2) {
        ctx.stroke(path, with: .color(line), lineWidth: width)
        ctx.fill(path, with: .color(fill))
    }

    // 好几个圆拼成一团（羊毛）
    private func fluff(_ ctx: GraphicsContext, _ circles: [(CGFloat, CGFloat, CGFloat)], fill: Color, line: Color) {
        var path = Path()
        for (x, y, r) in circles { path.addPath(circle(x, y, r)) }
        outlined(ctx, path, fill: fill, line: line)
    }

    private func eye(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, r: CGFloat = 1.35, onDark: Bool) {
        if onDark { ctx.fill(circle(x, y, r + 0.9), with: .color(.white)) }
        ctx.fill(circle(x, y, r), with: .color(Color(white: 0.08)))
        ctx.fill(circle(x + r * 0.35, y - r * 0.4, r * 0.4), with: .color(.white))   // 眼睛里的小高光
    }

    private func cheek(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        ctx.fill(oval(x, y, 3.4, 2), with: .color(Self.blush))
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rotation: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            .applying(CGAffineTransform(rotationAngle: rotation).concatenating(CGAffineTransform(translationX: x, y: y)))
    }

    private func triangle(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: a.0, y: a.1))
        path.addLine(to: CGPoint(x: b.0, y: b.1))
        path.addLine(to: CGPoint(x: c.0, y: c.1))
        path.closeSubpath()
        return path
    }
}
