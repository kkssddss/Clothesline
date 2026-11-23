import SwiftUI
import Observation

// Little animals walking back and forth on the rope.
// Drawn entirely in code with circles and ovals, on a 24×18 grid, facing right.
// Walking has two frames: the legs close and open, and the body lifts a little on the open frame.
// Now and then an animal stops to graze.

enum AnimalKind {
    case sheep, pig, cow, rooster
}

enum Pose {
    case walk0     // legs together
    case walk1     // legs apart (the body lifts a little)
    case nibble    // stopped, head down, grazing
}

// MARK: - The herd (moves every 70 ms)

@MainActor
@Observable
final class Herd {
    struct Member: Identifiable {
        let id: Int
        let kind: AnimalKind
        let scale: Double          // screen points per grid unit (the lamb is smaller)
        var x: Double
        var facing: Double         // 1 = facing right, -1 = facing left
        var nibble = 0             // ticks of grazing left
        var step = 0               // steps walked

        var pose: Pose { nibble > 0 ? .nibble : (step % 2 == 1 ? .walk1 : .walk0) }
        var bob: Double { pose == .walk1 ? -1 : 0 }
    }

    static let tick = 0.07                 // one tick = 70 ms
    static let stepTicks = 3               // switch legs every 3 ticks
    static let speed = 16.0                // grid units walked per second
    static let nibbleChance = 0.004        // 0.4% chance per tick of stopping to graze
    static let nibbleTicks = 18...36       // graze for 1.3 to 2.5 seconds

    var members: [Member] = []
    @ObservationIgnored var width: Double = 0
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var timer: Timer?

    func start(width: Double) {
        self.width = width
        guard timer == nil else { return }
        // Two sheep (one is a lamb), a pig, a cow and a rooster
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
                    // Reached the end: turn around and graze for a bit
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
}

struct AnimalsView: View {
    let rope: Rope
    @State private var herd = Herd()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(herd.members) { m in
                let x = CGFloat(m.x)
                let feet = (17.2 - 9) * m.scale        // distance from the canvas center to the feet
                AnimalSprite(kind: m.kind, pose: m.pose, scale: m.scale)
                    .scaleEffect(x: m.facing, y: 1)     // drawn facing right; mirrored when walking left
                    .rotationEffect(.radians(rope.angle(at: x)), anchor: UnitPoint(x: 0.5, y: 17.2 / 18))
                    .shadow(color: .black.opacity(0.3), radius: 1.2, y: 1)
                    .position(x: x, y: rope.y(at: x) - feet + 1 + m.bob)
                    .animation(.linear(duration: Herd.tick), value: m.x)   // glide smoothly between ticks
            }
        }
        .allowsHitTesting(false)                        // animals can't be clicked; clicks pass through
        .onAppear { herd.start(width: Double(rope.width)) }
        .onChange(of: rope.width) { _, width in herd.width = Double(width) }
    }
}

// MARK: - Drawing one animal

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

// All coordinates are grid units (24×18, origin at top left, facing right), multiplied by u when drawn
struct AnimalPainter {
    let u: CGFloat
    let pose: Pose

    static let wool = hex(0xfbfaf4), woolEdge = hex(0xa7aab2), face = hex(0x4b4f59)
    static let blush = hex(0xff9fb0), pupil = hex(0x111111)

    // legs in (1), out (-1), or even while grazing (0)
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

    // MARK: Sheep

    private func sheep(_ ctx: GraphicsContext) {
        fourLegs(ctx, color: Self.face, width: 1.7, top: 11.5)
        let puffs: [(CGFloat, CGFloat)] = [(6.5, 7.2), (9.8, 5.6), (13.4, 5.8), (16.0, 7.6), (15.2, 10.6),
                                           (11.0, 11.4), (7.0, 10.6), (4.6, 9.0), (10.8, 8.4)]
        // Draw the 9 puffs slightly larger in gray, then cover them in wool color → only a gray outline is left
        for (cx, cy) in puffs { fill(ctx, oval(cx - 3.8, cy - 3.8, cx + 3.8, cy + 3.8), Self.woolEdge) }
        for (cx, cy) in puffs { fill(ctx, oval(cx - 3.3, cy - 3.3, cx + 3.3, cy + 3.3), Self.wool) }
        let headY: CGFloat = nibbling ? 9.4 : 5.4
        fill(ctx, oval(17.4, headY, 23.2, headY + 5.6), Self.face)              // head
        fill(ctx, oval(17.0, headY + 0.4, 19.2, headY + 2.0), Self.face)        // ear
        eye(ctx, 20.9, headY + 2.0)
        fill(ctx, oval(21.0, headY + 3.6, 22.4, headY + 4.4), Self.blush)       // blush
    }

    // MARK: Pig

    private func pig(_ ctx: GraphicsContext) {
        let pink = Self.hex(0xffc8d2), edge = Self.hex(0xe48ea3), leg = Self.hex(0xf4a9b8)
        let snout = Self.hex(0xf7a3b4), nostril = Self.hex(0xc0647a)
        fourLegs(ctx, color: leg, width: 1.9, top: 10.8)
        ctx.stroke(oval(1.9, 6.0, 3.9, 8.0), with: .color(edge), lineWidth: 0.55 * u)  // curly tail
        fill(ctx, oval(3.0, 4.0, 18.0, 13.7), edge)
        fill(ctx, oval(3.5, 4.5, 17.5, 13.2), pink)                              // body
        let headY: CGFloat = nibbling ? 7.6 : 4.4
        fill(ctx, triangle((16.4, headY + 1.4), (17.2, headY - 1.4), (18.6, headY + 0.8)), leg)  // back ear
        fill(ctx, oval(15.3, headY - 0.5, 22.7, headY + 6.5), edge)
        fill(ctx, oval(15.8, headY, 22.2, headY + 6.0), pink)                    // head
        fill(ctx, triangle((17.8, headY + 1.0), (19.0, headY - 1.6), (20.2, headY + 0.8)), leg)  // front ear
        fill(ctx, oval(20.9, headY + 2.2, 23.8, headY + 4.6), snout)             // snout
        fill(ctx, oval(21.6, headY + 3.0, 22.2, headY + 3.8), nostril)
        fill(ctx, oval(22.6, headY + 3.0, 23.2, headY + 3.8), nostril)
        eye(ctx, 19.4, headY + 2.0)
        fill(ctx, oval(17.8, headY + 3.8, 19.2, headY + 4.6), Self.blush)
    }

    // MARK: Cow

    private func cow(_ ctx: GraphicsContext) {
        let white = Self.wool, edge = Self.woolEdge, spot = Self.face
        let muzzle = Self.hex(0xffc9cf), nostril = Self.hex(0xc0647a), horn = Self.hex(0xf3e2b3)
        fourLegs(ctx, color: white, width: 1.8, top: 10.5, edge: edge, hoof: spot)
        var tail = Path()                                                        // tail
        tail.move(to: pt(3.4, 6.2))
        tail.addQuadCurve(to: pt(2.2, 10.6), control: pt(1.8, 7.0))
        ctx.stroke(tail, with: .color(spot), style: StrokeStyle(lineWidth: 0.5 * u, lineCap: .round))
        fill(ctx, oval(1.5, 10.0, 2.9, 11.9), spot)
        fill(ctx, rounded(2.5, 4.1, 18.1, 13.1, 3.7), edge)
        let torso = rounded(3.0, 4.6, 17.6, 12.6, 3.2)
        fill(ctx, torso, white)                                                  // body
        var spots = ctx                                                          // black spots
        spots.clip(to: torso)
        fill(spots, oval(4.8, 5.0, 9.4, 8.8), spot)
        fill(spots, oval(10.6, 8.6, 15.0, 13.0), spot)
        fill(spots, oval(14.2, 3.8, 17.8, 7.0), spot)
        let headY: CGFloat = nibbling ? 7.6 : 3.6
        fill(ctx, oval(17.6, headY - 1.3, 18.8, headY + 0.6), horn)              // little horn
        fill(ctx, oval(20.4, headY - 1.3, 21.6, headY + 0.6), horn)
        fill(ctx, oval(15.4, headY + 0.6, 18.2, headY + 2.4), edge)
        fill(ctx, oval(15.7, headY + 0.9, 17.9, headY + 2.1), white)             // ear
        fill(ctx, oval(16.3, headY - 0.5, 22.9, headY + 6.3), edge)
        let head = oval(16.8, headY, 22.4, headY + 5.8)
        fill(ctx, head, white)                                                   // head
        var patch = ctx
        patch.clip(to: head)
        fill(patch, oval(16.0, headY - 1.0, 20.2, headY + 2.8), spot)           // black patch around the eye
        fill(ctx, oval(19.4, headY + 3.1, 23.8, headY + 6.2), muzzle)            // pink muzzle
        fill(ctx, oval(20.6, headY + 4.2, 21.2, headY + 5.0), nostril)
        fill(ctx, oval(22.0, headY + 4.2, 22.6, headY + 5.0), nostril)
        eye(ctx, 19.9, headY + 2.0)
    }

    // MARK: Rooster

    private func rooster(_ ctx: GraphicsContext) {
        let body = Self.hex(0xd9774a), edge = Self.hex(0xa9502c), wing = Self.hex(0xb85c34)
        let neck = Self.hex(0xf0a45a), neckEdge = Self.hex(0xc9783a)
        let red = Self.hex(0xe63946), yellow = Self.hex(0xf2b134)
        let feathers = [Self.hex(0x1f3d45), Self.hex(0x2f5d62), Self.hex(0x3e7a6e)]
        // Two yellow legs that also open and close, with three toes each
        for (index, lx) in [9.4, 11.8].enumerated() {
            let x0 = CGFloat(lx) + (index == 0 ? legShift : -legShift) * 0.6
            fill(ctx, rounded(x0, 12.6, x0 + 0.9, 17.2, 0.45), yellow)
            fill(ctx, rounded(x0 - 0.5, 16.5, x0 + 2.2, 17.2, 0.35), yellow)
        }
        // Big raised tail (three dark green feathers)
        fill(ctx, oval(1.0, 3.6, 8.6, 6.0, rotation: -0.95, around: (5.6, 7.6)), feathers[0])
        fill(ctx, oval(0.8, 6.0, 8.0, 8.4, rotation: -0.55, around: (5.6, 8.6)), feathers[1])
        fill(ctx, oval(1.2, 8.6, 7.8, 10.8, rotation: -0.15, around: (5.8, 9.6)), feathers[2])
        // Body and wing
        fill(ctx, oval(5.3, 6.1, 16.5, 14.9), edge)
        fill(ctx, oval(5.8, 6.6, 16.0, 14.4), body)
        fill(ctx, oval(7.2, 9.0, 12.8, 12.6), wing)
        // Neck and head (lowered while grazing)
        let dy: CGFloat = nibbling ? 3.0 : 0
        fill(ctx, oval(12.5, 4.3 + dy, 18.1, 11.5), neckEdge)
        fill(ctx, oval(13.0, 4.8 + dy, 17.6, 11.0), neck)
        fill(ctx, oval(13.1, 2.5 + dy, 18.9, 8.1 + dy), neckEdge)
        fill(ctx, oval(13.6, 3.0 + dy, 18.4, 7.6 + dy), neck)
        // Red comb and wattle, yellow beak
        fill(ctx, oval(14.0, 1.6 + dy, 15.8, 3.4 + dy), red)
        fill(ctx, oval(15.1, 1.0 + dy, 17.1, 3.0 + dy), red)
        fill(ctx, oval(16.4, 1.6 + dy, 18.0, 3.4 + dy), red)
        fill(ctx, triangle((18.2, 4.6 + dy), (20.4, 5.5 + dy), (18.2, 6.4 + dy)), yellow)
        fill(ctx, oval(17.4, 6.0 + dy, 18.8, 8.4 + dy), red)
        eye(ctx, 16.7, 4.8 + dy)
    }

    // MARK: Drawing helpers

    // Four upright legs in two pairs: one pair moves in while the other moves out
    private func fourLegs(_ ctx: GraphicsContext, color: Color, width: CGFloat, top: CGFloat,
                          edge: Color? = nil, hoof: Color? = nil) {
        for (index, lx) in [6.0, 9.0, 13.5, 16.5].enumerated() {
            let x0 = CGFloat(lx) + (index % 2 == 0 ? legShift : -legShift) * 0.6
            if let edge { fill(ctx, rounded(x0 - 0.4, top, x0 + width + 0.4, 17.6, 1.0), edge) }
            fill(ctx, rounded(x0, top, x0 + width, 17.2, 0.8), color)
            if let hoof { fill(ctx, rounded(x0, 16.0, x0 + width, 17.2, 0.6), hoof) }
        }
    }

    // White of the eye plus a pupil set slightly down and right, looking ahead
    private func eye(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        fill(ctx, oval(x - 0.9, y - 0.9, x + 0.9, y + 0.9), .white)
        fill(ctx, oval(x - 0.35, y - 0.35, x + 0.45, y + 0.45), Self.pupil)
    }

    private func fill(_ ctx: GraphicsContext, _ path: Path, _ color: Color) {
        ctx.fill(path, with: .color(color))
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

    // Oval from its top-left and bottom-right corners (like Pillow)
    private func oval(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x0 * u, y: y0 * u, width: (x1 - x0) * u, height: (y1 - y0) * u))
    }

    // Same, rotated around a point (for the rooster's tail feathers)
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
