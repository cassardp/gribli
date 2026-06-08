import SwiftUI

struct TileView: View {
    let tile: Tile
    let color: Color
    let isSelected: Bool
    let isBombFlashed: Bool
    let isPaused: Bool
    let isGameOver: Bool
    let size: CGFloat

    @State private var shakeTrigger = false

    private var baseScale: CGFloat {
        if isBombFlashed { return 1.15 }
        return isSelected ? 0.85 : 1
    }

    private var baseBrightness: Double {
        if isBombFlashed { return 0.3 }
        return isSelected ? 0.12 : 0
    }

    // Two-phase match pop: a fast opaque bloom + flash, then a collapse that
    // shrinks and fades out. Driven independently of the cascade's withAnimation
    // so the bloom always reads before gravity removes the tile.
    private struct PopValues {
        var scale: CGFloat = 1
        var brightness: Double = 0
        var opacity: Double = 1
    }

    var body: some View {
        Circle()
            .fill(isBombFlashed ? Palette.cream : color)
            .saturation(isPaused ? 0 : 1)
            .colorMultiply(isPaused ? Palette.sand : .white)
            .padding(4)
            .overlay {
                if tile.isBomb && !isBombFlashed {
                    Circle()
                        .fill(Palette.espresso)
                        .frame(width: size * 0.4, height: size * 0.4)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(baseScale)
            .brightness(baseBrightness)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeTrigger) { content, value in
                content.offset(x: value)
            } keyframes: { _ in
                let d: CGFloat = (tile.row + tile.col) % 2 == 0 ? 1 : -1
                CubicKeyframe(4 * d, duration: 0.15)
                CubicKeyframe(-3.5 * d, duration: 0.15)
                CubicKeyframe(3.5 * d, duration: 0.18)
                CubicKeyframe(-3 * d, duration: 0.18)
                CubicKeyframe(2.5 * d, duration: 0.2)
                CubicKeyframe(-2 * d, duration: 0.2)
                CubicKeyframe(1.5 * d, duration: 0.22)
                CubicKeyframe(-1 * d, duration: 0.22)
                CubicKeyframe(0.5 * d, duration: 0.25)
                CubicKeyframe(-0.2 * d, duration: 0.25)
                CubicKeyframe(0, duration: 0.3)
            }
            .keyframeAnimator(initialValue: CGFloat(1), trigger: tile.row * 8 + tile.col) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: 0.26)
                SpringKeyframe(0.93, duration: 0.10)
                SpringKeyframe(1.0, duration: 0.22, spring: .bouncy)
            }
            .keyframeAnimator(initialValue: PopValues(), trigger: tile.isMatched) { content, pop in
                content
                    .scaleEffect(pop.scale)
                    .brightness(pop.brightness)
                    .opacity(pop.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.35, duration: 0.10, spring: .snappy)
                    CubicKeyframe(0.2, duration: 0.18)
                }
                KeyframeTrack(\.brightness) {
                    CubicKeyframe(0.18, duration: 0.08)
                    CubicKeyframe(0, duration: 0.20)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: 0.10)
                    LinearKeyframe(0.0, duration: 0.18)
                }
            }
            .onChange(of: isGameOver) {
                if isGameOver {
                    Task {
                        try? await Task.sleep(for: .milliseconds((tile.row + tile.col) % 5 * 30))
                        shakeTrigger.toggle()
                    }
                }
            }
    }
}
