import SwiftUI

// The rope's shape: high at both ends, sagging in the middle
struct Rope: Sendable {
    var width: CGFloat
    var topY: CGFloat = 44      // height of the ends (leaves room above for the animals)
    var sag: CGFloat = 38       // how far the middle sags

    // rope height at x
    func y(at x: CGFloat) -> CGFloat {
        guard width > 0 else { return topY }
        let u = (x - width / 2) / (width / 2)          // -1 at the left end, 0 in the middle, 1 at the right end
        return topY + sag * (1 - u * u)
    }

    // rope angle at x (animals standing there tilt to match)
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
        // A control point at twice the sag draws exactly the y(at:) curve above
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rope.topY),
                          control: CGPoint(x: rect.width / 2, y: rope.topY + rope.sag * 2))
        return path
    }
}
