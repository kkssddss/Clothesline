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
