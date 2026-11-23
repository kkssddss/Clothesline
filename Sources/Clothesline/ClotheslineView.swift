import SwiftUI
import UniformTypeIdentifiers

struct ClotheslineView: View {
    @ObservedObject var store: LineStore
    var topInset: CGFloat = 0          // height taken by the menu bar at the top of the window

    var body: some View {
        GeometryReader { geo in
            let rope = Rope(width: geo.size.width, topY: topInset + 44)

            ZStack(alignment: .topLeading) {
                // The hanging screenshots and recordings; scrolls sideways when there are too many
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(store.items) { item in
                            HangingCard(item: item)
                                .onTapGesture { store.open(item) }
                                .contextMenu {
                                    Button("Open") { store.open(item) }
                                    Button("Show in Finder") { store.revealInFinder(item) }
                                    Divider()
                                    Button("Move to Trash", role: .destructive) { store.delete(item) }
                                }
                                .modifier(PullUpToDelete(item: item, store: store,
                                                         leaving: store.leaving.contains(item.id)))
                                .modifier(Sway(seed: item.seed))
                                // Using its position on screen: tilt to match that part of the rope, then move down to the rope's height,
                                // so the picture's top edge sits right on the rope
                                .visualEffect { content, proxy in
                                    let x = proxy.frame(in: .global).midX
                                    return content
                                        .rotationEffect(.radians(rope.angle(at: x)), anchor: .top)
                                        .offset(y: rope.y(at: x) - rope.topY)
                                }
                                // New pictures fade in. A deleted one is already out of sight when its animation ends, so just remove it
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                                                        removal: .identity))
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, rope.topY - 2)          // picture tops sit on the rope (2 pt higher, so the rope covers the top edge)
                    .padding(.bottom, rope.sag + 12)
                }
                .scrollClipDisabled()                      // flying pictures can leave the scroll area

                // The rope (drawn in front of the pictures)
                RopeShape(rope: rope)
                    .stroke(Color(red: 0.66, green: 0.52, blue: 0.38),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .overlay(
                        RopeShape(rope: rope)
                            .stroke(Color.white.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .allowsHitTesting(false)

                // The animals
                AnimalsView(rope: rope)
            }
        }
        .animation(.spring(duration: 0.5), value: store.items.map(\.id))
    }
}

// Hold a picture to drag it anywhere; it follows the mouse:
//   pull it up more than 70 pt and let go → delete (flips twice, blows away)
//   let go before that → springs back onto the rope
//   drag it down → drop the file into another app (WeChat, Word...)
struct PullUpToDelete: ViewModifier {
    let item: LineItem
    let store: LineStore
    let leaving: Bool                           // flying away
    @State private var pull: CGSize = .zero
    @State private var flight = 0.0             // fly-away animation progress (0 to 1)
    @State private var draggingFile = false
    @GestureState private var pressing = false  // still held down (turns false by itself if the drag is interrupted)
    private let threshold: CGFloat = 70

    func body(content: Content) -> some View {
        let ready = pull.height < -threshold && !leaving
        content
            .overlay(alignment: .top) {
                if ready {
                    // Pulled far enough: a small trash can shows that letting go deletes it
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
            .animation(.spring(duration: 0.2), value: ready)      // animate only the trash can and the zoom, not the drag itself
            .offset(pull)                                          // follow the mouse
            .modifier(FloatAway(progress: flight))
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        guard !leaving, !draggingFile else { return }
                        let t = value.translation
                        // Clearly dragging down: drag the file out instead
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
                            store.delete(item)                     // fly away from where it was pulled to
                        } else {
                            springBack()
                        }
                    }
            )
            .allowsHitTesting(!leaving)
            .onChange(of: pressing) { _, isPressing in
                // Released (or the drag was interrupted): spring back unless it's flying away
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

// Delete animation: flips over twice, then a light wind carries it off, shrinking as it goes (kept small so it's easy on the eyes)
struct FloatAway: ViewModifier, Animatable {
    var progress: Double     // 0 = hanging, 1 = gone

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        // First 45%: flip over twice (slow-fast-slow), shrinking while flipping, with almost no perspective so it never suddenly grows.
        // After the two flips it tips another 78° and lies flat, like a sheet of paper carried by the wind
        let a = min(p / 0.45, 1)
        let flip = a * a * (3 - 2 * a)
        // Last 55%: lying flat, it drifts up and to the right, smaller and fainter, bobbing slightly
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

// Wind: a few white streaks sweep from left to right, each curling at the end
struct WindStreaks: View {
    let progress: Double

    // Each streak: height, start, end (as fractions of the canvas), curl size, start time, line width
    private static let streaks: [(y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double)] = [
        (0.55, 0.05, 0.70, 9, 0.30, 1.4),
        (0.30, 0.15, 0.80, 7, 0.40, 1.2),
        (0.75, 0.10, 0.65, 0, 0.48, 1.0),
    ]

    var body: some View {
        Canvas { context, size in
            for streak in Self.streaks {
                let life = (progress - streak.delay) / 0.45          // each streak lasts 45% of the animation
                guard life > 0, life < 1 else { continue }
                let path = Self.path(streak, in: size).trimmedPath(from: max(0, life - 0.4), to: life)
                context.stroke(path, with: .color(.white.opacity(0.45 * sin(life * .pi))),
                               style: StrokeStyle(lineWidth: streak.width, lineCap: .round))
            }
        }
        .frame(width: 260, height: 170)
        .shadow(color: .black.opacity(0.15), radius: 1)     // faint, but still visible on light backgrounds
        .allowsHitTesting(false)
    }

    private static func path(_ s: (y: Double, from: Double, to: Double, curl: Double, delay: Double, width: Double),
                             in size: CGSize) -> Path {
        let y = s.y * size.height
        let x0 = s.from * size.width, x1 = s.to * size.width
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y))
        // wavy line to the right
        path.addCurve(to: CGPoint(x: x1, y: y - 12),
                      control1: CGPoint(x: x0 + (x1 - x0) * 0.35, y: y - 16),
                      control2: CGPoint(x: x0 + (x1 - x0) * 0.65, y: y + 10))
        // small curl at the end
        if s.curl > 0 {
            path.addArc(center: CGPoint(x: x1, y: y - 12 - s.curl), radius: s.curl,
                        startAngle: .degrees(90), endAngle: .degrees(-200), clockwise: true)
        }
        return path
    }
}

// Gentle swaying; each picture swings by a different amount and speed
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
                .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)   // a shadow keeps it readable on the transparent background
                .lineLimit(1)
                .frame(maxWidth: 140)
        }
    }

    private func fitted(_ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // No frame, just the picture itself
    @ViewBuilder
    private var picture: some View {
        if let preview = item.preview {
            // Sized from the picture's own aspect ratio (max 140×88) so the frame matches the picture and its top edge is at the top
            let size = fitted(preview.size, maxWidth: 140, maxHeight: 88)
            Image(nsImage: preview)
                .resizable()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if item.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                }
                // Screenshots that were only on the clipboard get a small badge in the bottom-right corner
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
