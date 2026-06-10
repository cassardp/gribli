import SwiftUI

struct TileView: View {
    let tile: Tile
    let color: Color
    let isSelected: Bool
    let isHinted: Bool
    let isBombFlashed: Bool
    let isPaused: Bool
    let isGameOver: Bool
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gameOverWave = false

    // Squash & stretch when a tile lands after a fall, anchored at the bottom
    // of the cell so the impact reads as weight, not as a generic scale blip.
    private struct LandingValues {
        var sx: CGFloat = 1
        var sy: CGFloat = 1
    }

    // Match pop: a clean, direct collapse — the tile shrinks away with a
    // fade. Driven independently of the cascade's withAnimation so it always
    // completes before gravity removes the tile.
    private struct PopValues {
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

    // Game-over "deflate" wave: a small hop + squash that sweeps diagonally
    // across the board, staggered per tile.
    private struct WaveValues {
        var scale: CGFloat = 1
        var dip: CGFloat = 0
    }

    private var baseScale: CGFloat {
        if isBombFlashed { return 1.18 }
        if isSelected { return 0.88 }
        return isHinted ? 1.04 : 1
    }

    var body: some View {
        Circle()
            .fill(isBombFlashed ? Palette.cream : color)
            .saturation(isPaused ? 0 : 1)
            .colorMultiply(isPaused ? Palette.sand : .white)
            .padding(4)
            .overlay {
                if tile.isBomb && !isBombFlashed {
                    bombCore
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(baseScale)
            .brightness(isBombFlashed ? 0.3 : (isSelected ? 0.1 : 0))
            .animation(
                isSelected
                    ? (reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .easeInOut(duration: 0.55).repeatForever(autoreverses: true))
                    : .spring(duration: 0.25, bounce: 0.4),
                value: isSelected
            )
            // Idle hint: a barely-there breathing pulse on the two tiles of a
            // valid swap. With reduce motion, a static 4% bump instead.
            .animation(
                isHinted
                    ? (reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .easeInOut(duration: 0.6).repeatForever(autoreverses: true))
                    : .easeOut(duration: 0.2),
                value: isHinted
            )
            .keyframeAnimator(initialValue: LandingValues(), trigger: tile.row) { content, v in
                content.scaleEffect(x: v.sx, y: v.sy, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack(\.sx) {
                    LinearKeyframe(1.0, duration: 0.2)
                    SpringKeyframe(1.12, duration: 0.07, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
                }
                KeyframeTrack(\.sy) {
                    LinearKeyframe(1.0, duration: 0.2)
                    SpringKeyframe(0.84, duration: 0.07, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
                }
            }
            .keyframeAnimator(initialValue: PopValues(), trigger: tile.isMatched) { content, pop in
                content
                    .scaleEffect(pop.scale)
                    .opacity(pop.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.0, duration: 0.2)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: 0.06)
                    LinearKeyframe(0.0, duration: 0.14)
                }
            }
            .keyframeAnimator(initialValue: WaveValues(), trigger: gameOverWave) { content, v in
                content
                    .scaleEffect(v.scale)
                    .offset(y: v.dip)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.07, duration: 0.12)
                    SpringKeyframe(0.9, duration: 0.16, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                }
                KeyframeTrack(\.dip) {
                    CubicKeyframe(-7, duration: 0.12)
                    SpringKeyframe(5, duration: 0.16, spring: .snappy)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
            }
            .onChange(of: isGameOver) {
                if isGameOver {
                    Task {
                        try? await Task.sleep(for: .milliseconds((tile.row + tile.col) * 45))
                        gameOverWave.toggle()
                    }
                }
            }
    }

    private var bombCore: some View {
        Group {
            if reduceMotion {
                Circle()
                    .fill(Palette.espresso)
                    .frame(width: size * 0.4, height: size * 0.4)
            } else {
                Circle()
                    .fill(Palette.espresso)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .phaseAnimator([1.0, 1.22]) { dot, pulse in
                        dot.scaleEffect(pulse)
                    } animation: { _ in .easeInOut(duration: 0.7) }
            }
        }
    }
}
