import SwiftUI

struct TileView: View {
    let tile: Tile
    let color: Color
    let isSelected: Bool
    let isBombFlashed: Bool
    let isPaused: Bool
    let isGameOver: Bool
    let size: CGFloat

    @State private var bombPulse = false
    @State private var shakeTrigger = false

    var body: some View {
        Circle()
            .fill(isBombFlashed ? .white : color)
            .saturation(isPaused ? 0 : 1)
            .padding(4)
            .overlay {
                if tile.isBomb && !isBombFlashed {
                    Circle()
                        .fill(.black)
                        .frame(width: size * 0.4, height: size * 0.4)
                        .scaleEffect(bombPulse ? 1.2 : 0.85)
                        .opacity(bombPulse ? 1 : 0.7)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isBombFlashed ? 1.15 : (isSelected ? 0.85 : 1))
            .brightness(isBombFlashed ? 0.3 : (isSelected ? 0.12 : 0))
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
            .opacity(tile.isMatched ? 0 : 1)
            .onAppear {
                if tile.isBomb {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        bombPulse = true
                    }
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
