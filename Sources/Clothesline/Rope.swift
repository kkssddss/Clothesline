import SwiftUI

// 晾衣绳的形状：两头高、中间往下垂
struct Rope: Sendable {
    var width: CGFloat
    var topY: CGFloat = 44      // 两头的高度（上面留点地方给小动物跳）
    var sag: CGFloat = 38       // 中间往下垂多少

    // 绳子在 x 这个位置的高度
    func y(at x: CGFloat) -> CGFloat {
        guard width > 0 else { return topY }
        let u = (x - width / 2) / (width / 2)          // 最左 -1，中间 0，最右 1
        return topY + sag * (1 - u * u)
    }

    // 绳子在 x 这个位置的倾斜角度（小动物站上去要跟着斜）
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
        // 控制点放在 2 倍下垂的位置，画出来正好是上面 y(at:) 那条曲线
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rope.topY),
                          control: CGPoint(x: rect.width / 2, y: rope.topY + rope.sag * 2))
        return path
    }
}

// 在绳子上走来走去的小动物
struct WalkingAnimal: Identifiable {
    let id: Int
    let emoji: String
    let speed: Double      // 每秒走多少点
    let start: Double      // 起点错开，大家不挤在一起
}

struct AnimalsView: View {
    let rope: Rope
    @State private var animals = AnimalsView.makeAnimals()
    @State private var hopStarts: [Int: Date] = [:]

    static let emojis = ["🐄", "🐖", "🐑", "🐎", "🐓", "🦆", "🐇", "🐈"]

    static func makeAnimals(count: Int = 5) -> [WalkingAnimal] {
        emojis.shuffled().prefix(count).enumerated().map { index, emoji in
            WalkingAnimal(id: index, emoji: emoji,
                          speed: .random(in: 14...32), start: .random(in: 0...5000))
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(animals) { animal in
                    let (x, facingRight) = walk(animal, at: t)
                    let beat = t * animal.speed / 9           // 走路的节拍
                    let bob = abs(sin(beat * .pi)) * 3        // 一颠一颠
                    let wobble = sin(beat * .pi) * 0.08       // 左右晃
                    Text(animal.emoji)
                        .font(.system(size: 26))
                        .onTapGesture { hopStarts[animal.id] = Date() }   // 点一下跳一下
                        .scaleEffect(x: facingRight ? -1 : 1, y: 1)        // emoji 默认朝左，往右走就翻过来
                        .rotationEffect(.radians(rope.angle(at: x) + wobble), anchor: .bottom)
                        .position(x: x, y: rope.y(at: x) - 14 - bob - hop(animal.id, now: timeline.date))
                }
            }
        }
    }

    // 在绳子上从一头走到另一头，再走回来
    private func walk(_ animal: WalkingAnimal, at t: Double) -> (CGFloat, Bool) {
        let margin: Double = 30
        let length = max(Double(rope.width) - margin * 2, 1)
        let d = (animal.start + t * animal.speed).truncatingRemainder(dividingBy: length * 2)
        return d < length ? (CGFloat(margin + d), true) : (CGFloat(margin + length * 2 - d), false)
    }

    private func hop(_ id: Int, now: Date) -> CGFloat {
        guard let start = hopStarts[id] else { return 0 }
        let p = now.timeIntervalSince(start) / 0.5     // 跳一下 0.5 秒
        guard p < 1 else { return 0 }
        return CGFloat(4 * 28 * p * (1 - p))           // 最高跳 28 点
    }
}
