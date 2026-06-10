import SwiftUI

private struct SplashTile: Identifiable {
    let id = UUID()
    let colorIndex: Int
    var position: Int
}

struct SplashView: View {
    let onPlay: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PaletteStore.self) private var palette

    private var tileColors: [Color] {
        [palette.olive, palette.orangeRed, palette.orange,
         palette.blueGray, palette.silver, palette.taupe]
    }

    // [A, A, B, A, B, B] — swap pos 2↔3 → AAA + BBB → all matched
    // Fixed colors: red (index 1) and silver (index 4)
    @State private var tiles: [SplashTile] = [
        SplashTile(colorIndex: 1, position: 0),
        SplashTile(colorIndex: 1, position: 1),
        SplashTile(colorIndex: 4, position: 2),
        SplashTile(colorIndex: 1, position: 3),
        SplashTile(colorIndex: 4, position: 4),
        SplashTile(colorIndex: 4, position: 5),
    ]

    @State private var matchedPositions: Set<Int> = []
    @State private var collapsedPositions: Set<Int> = []
    @State private var hintedPositions: Set<Int> = []
    @State private var completed = false
    @State private var isSwapping = false

    @State private var dragTileId: UUID?
    @State private var raisedTileId: UUID?
    @State private var dragOffsets: [UUID: CGFloat] = [:]
    @State private var dragPastThreshold = false

    @State private var titleOffset: CGFloat = -40
    @State private var titleOpacity: Double = 0
    @State private var tilesOffset: CGFloat = 40
    @State private var tilesOpacity: Double = 0
    @State private var hintOpacity: Double = 0

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

            instructionView
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
            scheduleHint(after: 1.4)
        }
    }

    // MARK: - Instruction

    private var instructionView: some View {
        ZStack {
            if completed {
                Text("You got it!")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    Text("Swipe")
                    Circle()
                        .fill(tileColors[4])
                        .frame(width: 20, height: 20)
                    Text("right")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .font(.system(size: 17, weight: .medium, design: .rounded))
        .foregroundStyle(textColor.opacity(0.6))
        .frame(height: 28)
        .clipped()
    }

    // MARK: - Tiles

    private var splashTiles: some View {
        GeometryReader { geo in
            // Same tile size as the game grid (width / 8)
            let tileSize = geo.size.width / 8
            let tilesWidth = tileSize * 6
            let leadingPad = (geo.size.width - tilesWidth) / 2

            ZStack {
                ForEach(tiles) { tile in
                    tileView(tile, tileSize: tileSize, leadingPad: leadingPad, centerY: geo.size.height / 2)
                }
            }
            .offset(y: tilesOffset)
            .opacity(tilesOpacity)
        }
        .frame(height: UIScreen.main.bounds.width / 8)
        .padding(.horizontal)
    }

    private func tileView(_ tile: SplashTile, tileSize: CGFloat, leadingPad: CGFloat, centerY: CGFloat) -> some View {
        let isMatched = matchedPositions.contains(tile.position)
        let isCollapsed = collapsedPositions.contains(tile.position)
        let isHinted = hintedPositions.contains(tile.position)
        let isDragging = dragTileId == tile.id
        let posX = leadingPad + CGFloat(tile.position) * tileSize + tileSize / 2 + (dragOffsets[tile.id] ?? 0)

        // Idle hint: same barely-there breathing pulse as the in-game hint.
        // With reduce motion, a static 4% bump instead.
        let hintAnimation: Animation = isHinted
            ? (reduceMotion
                ? .easeOut(duration: 0.2)
                : .easeInOut(duration: 0.6).repeatForever(autoreverses: true))
            : .easeOut(duration: 0.2)

        return Circle()
            .fill(tileColors[tile.colorIndex])
            .padding(4)
            .frame(width: tileSize, height: tileSize)
            .scaleEffect(isHinted ? 1.04 : 1.0)
            .animation(hintAnimation, value: isHinted)
            .brightness(isMatched && !isCollapsed ? 0.12 : 0)
            .scaleEffect(isCollapsed ? 0 : (isMatched ? 1.05 : 1.0))
            .opacity(isCollapsed ? 0 : 1)
            .scaleEffect(isDragging ? 1.07 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: 7, y: 4)
            .animation(.snappy(duration: 0.18), value: isDragging)
            .position(x: posX, y: centerY)
            .zIndex(zIndex(for: tile))
            .gesture(tileDragGesture(tile, tileSize: tileSize))
    }

    // The grabbed tile rides above its swap partner for the whole exchange,
    // drag and release slide included — zIndex is not animatable.
    private func zIndex(for tile: SplashTile) -> Double {
        if dragTileId == tile.id || raisedTileId == tile.id { return 2 }
        return dragOffsets.keys.contains(tile.id) ? 1 : 0
    }

    // MARK: - Gesture

    private func tileDragGesture(_ tile: SplashTile, tileSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !completed, !isSwapping else { return }
                let t = value.translation

                if dragTileId == nil {
                    guard abs(t.width) >= 4, abs(t.width) > abs(t.height) else { return }
                    dragTileId = tile.id
                    hintedPositions = []
                }
                guard dragTileId == tile.id else { return }

                let raw = t.width
                let dir = raw >= 0 ? 1 : -1
                let neighborPos = tile.position + dir
                let hasNeighbor = neighborPos >= 0 && neighborPos < 6

                // Same feel as the game grid: follow the finger 1:1 up to just
                // past the commit threshold, then rubber-band so the release
                // always has a visible spring left to play. Against an edge,
                // allow only a small give.
                let pull: CGFloat
                if hasNeighbor {
                    let soft = tileSize * 0.55
                    let k = tileSize * 0.2
                    let mag = abs(raw)
                    let eased = mag <= soft ? mag : soft + k * (1 - exp(-(mag - soft) / k))
                    pull = eased * (raw >= 0 ? 1 : -1)
                } else {
                    let limit = tileSize * 0.18
                    pull = min(max(raw, -limit), limit)
                }
                if hasNeighbor, let neighbor = tiles.first(where: { $0.position == neighborPos }) {
                    dragOffsets = [tile.id: pull, neighbor.id: -pull]
                } else {
                    dragOffsets = [tile.id: pull]
                }

                let past = hasNeighbor && abs(pull) > tileSize * 0.5
                if past != dragPastThreshold {
                    dragPastThreshold = past
                    if past { lightHaptic() }
                }
            }
            .onEnded { value in
                let wasLocked = dragTileId == tile.id
                dragTileId = nil
                dragPastThreshold = false
                guard wasLocked, !completed, !isSwapping else {
                    withAnimation(.bouncy(duration: 0.25)) { dragOffsets = [:] }
                    return
                }

                let raw = value.translation.width
                let dir = raw >= 0 ? 1 : -1
                let neighborPos = tile.position + dir
                let hasNeighbor = neighborPos >= 0 && neighborPos < 6

                // A fast flick commits even under half a tile of travel.
                let predicted = value.predictedEndTranslation.width
                let flick = predicted * raw > 0 && abs(predicted) > tileSize * 0.9 && abs(raw) > tileSize * 0.2

                if hasNeighbor && (abs(raw) > tileSize * 0.5 || flick) {
                    raisedTileId = tile.id
                    commitSwap(tile.position, neighborPos)
                } else {
                    withAnimation(.bouncy(duration: 0.25)) { dragOffsets = [:] }
                }
            }
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

    private func commitSwap(_ posA: Int, _ posB: Int) {
        isSwapping = true
        withAnimation(.spring(duration: 0.24, bounce: 0.25)) {
            dragOffsets = [:]
            swapPositions(posA, posB)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            let matches = findMatch()
            if matches.isEmpty {
                // No match: bouncy back-and-forth refusal with a firm clack,
                // same as the game grid.
                rigidHaptic()
                withAnimation(.spring(duration: 0.34, bounce: 0.5)) {
                    swapPositions(posA, posB)
                }
                try? await Task.sleep(for: .milliseconds(300))
                raisedTileId = nil
                isSwapping = false
                scheduleHint(after: 1.5)
            } else {
                mediumHaptic()
                raisedTileId = nil
                hintedPositions = []
                withAnimation(.spring(duration: 0.3)) {
                    completed = true
                    matchedPositions = matches
                }
                await celebrate(from: (CGFloat(posA) + CGFloat(posB)) / 2)
            }
        }
    }

    // MARK: - Hint

    private func scheduleHint(after seconds: Double) {
        Task {
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !completed, !isSwapping, dragTileId == nil else { return }
            hintedPositions = [2, 3]
        }
    }

    // MARK: - Completion

    // Sober collapse: each tile shrinks away with a fade, staggered outward
    // from the swap point — same vocabulary as the in-game match pop.
    private func celebrate(from center: CGFloat) async {
        try? await Task.sleep(for: .milliseconds(280))
        for tile in tiles {
            let distance = abs(CGFloat(tile.position) - center)
            let delay = reduceMotion ? 0 : Double(distance) * 0.06
            withAnimation(.easeIn(duration: 0.22).delay(delay)) {
                _ = collapsedPositions.insert(tile.position)
            }
        }
        try? await Task.sleep(for: .milliseconds(650))
        dismiss()
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            hintOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.4)) {
            titleOpacity = 0
            titleOffset = -20
            tilesOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            onPlay()
        }
    }

    // MARK: - Haptics

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
    private func lightHaptic() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
    }
    private func mediumHaptic() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8) }
    }
    private func rigidHaptic() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8) }
    }
}
