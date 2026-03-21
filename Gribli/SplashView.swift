import SwiftUI

private struct SplashTile: Identifiable {
    let id = UUID()
    let colorIndex: Int
    var position: Int
}

struct SplashView: View {
    let onPlay: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private static let tileColors: [Color] = [
        Palette.olive, Palette.orangeRed, Palette.orange,
        Palette.blueGray, Palette.silver, Palette.taupe
    ]

    // [A, A, B, A, B, B] — swap pos 2↔3 → AAA + BBB → all matched
    @State private var tiles: [SplashTile] = {
        var indices = Array(0..<tileColors.count)
        indices.shuffle()
        let a = indices[0], b = indices[1]
        return [
            SplashTile(colorIndex: a, position: 0),
            SplashTile(colorIndex: a, position: 1),
            SplashTile(colorIndex: b, position: 2),
            SplashTile(colorIndex: a, position: 3),
            SplashTile(colorIndex: b, position: 4),
            SplashTile(colorIndex: b, position: 5),
        ]
    }()

    @State private var matchedPositions: Set<Int> = []
    @State private var completed = false
    @State private var exploding = false
    @State private var isSwapping = false

    @State private var titleOffset: CGFloat = -40
    @State private var titleOpacity: Double = 0
    @State private var tilesOffset: CGFloat = 40
    @State private var tilesOpacity: Double = 0
    @State private var hintOpacity: Double = 0

    @State private var demoActive = false
    @State private var userInteracted = false
    @State private var demoSwapped = false
    @State private var demoFingerX: CGFloat = 0
    @State private var demoFingerOpacity: Double = 0
    @State private var cachedTileSize: CGFloat = 0
    @State private var cachedLeadingPad: CGFloat = 0

    @State private var explosionOffsets: [UUID: (x: CGFloat, y: CGFloat, rotation: Double)] = [:]

    private var bgColor: Color { Palette.background(for: colorScheme) }
    private var textColor: Color { Palette.text(for: colorScheme) }

    var body: some View {
        VStack(spacing: 48) {
            Text("Gribli")
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(textColor)
                .offset(y: titleOffset)
                .opacity(titleOpacity)

            splashTiles

            Text("Swipe")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(textColor.opacity(0.4))
                .opacity(hintOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.4).delay(0.1)) {
                titleOffset = 0
                titleOpacity = 1.0
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(0.3)) {
                tilesOffset = 0
                tilesOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.6).delay(0.8)) {
                hintOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                startDemoLoop()
            }
        }
    }

    // MARK: - Tiles

    private var splashTiles: some View {
        GeometryReader { geo in
            // Same tile size as the game grid (width / 8)
            let tileSize = geo.size.width / 8
            let tilesWidth = tileSize * 6
            let leadingPad = (geo.size.width - tilesWidth) / 2

            ZStack {
                Color.clear.onAppear {
                    cachedTileSize = tileSize
                    cachedLeadingPad = leadingPad
                }

                ForEach(tiles) { tile in
                    let isMatched = matchedPositions.contains(tile.position)
                    let offsets = explosionOffsets[tile.id] ?? (x: 0.0, y: 0.0, rotation: 0.0)

                    Circle()
                        .fill(Self.tileColors[tile.colorIndex])
                        .padding(4)
                        .frame(width: tileSize, height: tileSize)
                        .scaleEffect(isMatched && !exploding ? 1.15 : 1.0)
                        .brightness(isMatched && !exploding ? 0.12 : 0)
                        .offset(x: exploding ? offsets.x : 0, y: exploding ? offsets.y : 0)
                        .rotationEffect(.degrees(exploding ? offsets.rotation : 0))
                        .scaleEffect(exploding ? 0.4 : 1.0)
                        .opacity(exploding ? 0 : 1)
                        .position(
                            x: leadingPad + CGFloat(tile.position) * tileSize + tileSize / 2,
                            y: geo.size.height / 2
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    cancelDemo()
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    guard abs(dx) >= 15, abs(dx) > abs(dy),
                                          !completed, !isSwapping else { return }
                                    handleSwipe(tilePosition: tile.position, direction: dx > 0 ? 1 : -1)
                                }
                        )
                }

                Circle()
                    .fill(textColor.opacity(0.18))
                    .frame(width: tileSize * 0.7, height: tileSize * 0.7)
                    .position(x: demoFingerX, y: geo.size.height / 2)
                    .opacity(demoFingerOpacity)
            }
            .offset(y: tilesOffset)
            .opacity(tilesOpacity)
        }
        .frame(height: UIScreen.main.bounds.width / 8)
        .padding(.horizontal)
    }

    // MARK: - Swap & Match

    private func swapPositions(_ posA: Int, _ posB: Int) {
        guard let ia = tiles.firstIndex(where: { $0.position == posA }),
              let ib = tiles.firstIndex(where: { $0.position == posB }) else { return }
        tiles[ia].position = posB
        tiles[ib].position = posA
    }

    private func findMatch() -> Set<Int> {
        let sorted = tiles.sorted { $0.position < $1.position }
        var matched = Set<Int>()
        var i = 0
        while i < sorted.count {
            var j = i + 1
            while j < sorted.count, sorted[j].colorIndex == sorted[i].colorIndex { j += 1 }
            if j - i >= 3 {
                for k in i..<j { matched.insert(sorted[k].position) }
            }
            i = j
        }
        return matched
    }

    private func handleSwipe(tilePosition: Int, direction: Int) {
        let neighborPos = tilePosition + direction
        guard neighborPos >= 0, neighborPos < 6 else { return }

        isSwapping = true
        lightHaptic()

        withAnimation(.spring(duration: 0.25)) {
            swapPositions(tilePosition, neighborPos)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let matches = findMatch()
            if matches.isEmpty {
                withAnimation(.spring(duration: 0.25)) {
                    swapPositions(tilePosition, neighborPos)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isSwapping = false
                }
            } else {
                mediumHaptic()
                withAnimation(.spring(duration: 0.2)) {
                    matchedPositions = matches
                }
                completed = true
                completeSplash()
            }
        }
    }

    // MARK: - Demo

    private func startDemoLoop() {
        guard !userInteracted, !completed else { return }
        demoActive = true

        let tileSize = cachedTileSize
        let leading = cachedLeadingPad
        guard tileSize > 0 else { return }

        let startX = leading + 2 * tileSize + tileSize / 2
        let endX = leading + 3 * tileSize + tileSize / 2
        demoFingerX = startX

        withAnimation(.easeOut(duration: 0.25)) {
            demoFingerOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard demoActive else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                demoFingerX = endX
            }
            withAnimation(.spring(duration: 0.3)) {
                swapPositions(2, 3)
                demoSwapped = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard demoActive else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                matchedPositions = Set(0..<6)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard demoActive else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                matchedPositions = []
                demoFingerOpacity = 0
            }
            withAnimation(.spring(duration: 0.3)) {
                swapPositions(2, 3)
                demoSwapped = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard demoActive else { return }
            startDemoLoop()
        }
    }

    private func cancelDemo() {
        guard !userInteracted else { return }
        userInteracted = true
        demoActive = false
        demoFingerOpacity = 0
        matchedPositions = []
        if demoSwapped {
            swapPositions(2, 3)
            demoSwapped = false
        }
    }

    // MARK: - Completion

    private func completeSplash() {
        generateExplosionOffsets()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.15)) {
                hintOpacity = 0
            }
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
                exploding = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                titleOpacity = 0
                titleOffset = -20
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                onPlay()
            }
        }
    }

    private func generateExplosionOffsets() {
        let center: CGFloat = 2.5
        for tile in tiles {
            let spread = CGFloat(tile.position) - center
            let x = spread * CGFloat.random(in: 60...100) + CGFloat.random(in: -30...30)
            let y = CGFloat.random(in: -300 ... -150)
            let rotation = Double(spread) * Double.random(in: 15...35)
            explosionOffsets[tile.id] = (x, y, rotation)
        }
    }

    private func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }
    private func mediumHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }
}
