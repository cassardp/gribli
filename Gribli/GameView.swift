import SwiftUI

struct GameView: View {
    @State private var viewModel: GameViewModel

    @State private var barFillAnimating = false
    @State private var showLeaderboard = false
    @State private var leaderboardProfileMode = 0
    @State private var leaderboardId = UUID()
    @State private var showPauseHint = false
    @State private var dragTileId: UUID?
    @State private var dragAxis: Axis?
    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var dragPastThreshold = false
    @State private var raisedTileId: UUID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PaletteStore.self) private var palette
    private var bgColor: Color { Palette.background(for: colorScheme) }
    private var textColor: Color { Palette.text(for: colorScheme) }
    private var isUrgent: Bool { viewModel.timeRemaining <= 10 && viewModel.timeRemaining > 0 && viewModel.hasStarted && !viewModel.isGameOver }

    init() {
        _viewModel = State(initialValue: GameViewModel())
    }

    // The grabbed tile rides above its swap partner for the whole exchange —
    // during the drag (dragTileId) and through the release slide (raisedTileId).
    private func zIndex(for tile: Tile) -> Double {
        if tile.isMatched { return 3 }
        if dragTileId == tile.id || raisedTileId == tile.id { return 2 }
        return dragOffsets.keys.contains(tile.id) ? 1 : 0
    }

    private func tileDragGesture(_ tile: Tile, tileSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !viewModel.isAnimating, !viewModel.isGameOver, !viewModel.isPaused else { return }
                let t = value.translation

                // Lock onto one axis as soon as the finger direction is
                // readable. A low threshold keeps the tile glued to the finger
                // from the first points — no perceptible dead zone.
                if dragTileId == nil {
                    guard max(abs(t.width), abs(t.height)) >= 4 else { return }
                    dragTileId = tile.id
                    dragAxis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                    viewModel.cancelHint()
                }
                guard dragTileId == tile.id, let axis = dragAxis else { return }

                let raw = axis == .horizontal ? t.width : t.height
                let dir = raw >= 0 ? 1 : -1
                let nr = tile.row + (axis == .vertical ? dir : 0)
                let nc = tile.col + (axis == .horizontal ? dir : 0)
                let hasNeighbor = nr >= 0 && nr < viewModel.engine.rows && nc >= 0 && nc < viewModel.engine.cols

                func offset(_ d: CGFloat) -> CGSize {
                    axis == .horizontal ? CGSize(width: d, height: 0) : CGSize(width: 0, height: d)
                }

                // Follow the finger 1:1 up to just past the commit threshold,
                // then rubber-band: the swap never completes under the finger,
                // so the release always has a visible spring left to play —
                // even on a fast flick. The over-threshold zone decays
                // exponentially with its slope starting at 1, so the hand-off
                // from 1:1 tracking is seamless and the ~0.75-tile ceiling is
                // approached asymptotically — no kink, no hard stop, which a
                // slow drag would otherwise feel as a snag. With no neighbour
                // that way, allow only a small give against the edge.
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
                if hasNeighbor {
                    dragOffsets = [tile.id: offset(pull), viewModel.engine.grid[nr][nc].id: offset(-pull)]
                } else {
                    dragOffsets = [tile.id: offset(pull)]
                }

                let past = hasNeighbor && abs(pull) > tileSize * 0.5
                if past != dragPastThreshold {
                    dragPastThreshold = past
                    if past { viewModel.swapThresholdHaptic() }
                }
            }
            .onEnded { value in
                let wasLocked = dragTileId == tile.id && dragAxis != nil
                let lockedAxis = dragAxis
                dragTileId = nil
                dragAxis = nil
                dragPastThreshold = false
                let t = value.translation

                if wasLocked {
                    // Keep the released tile above its neighbours until the
                    // commit/cancel slide finishes — zIndex is not animatable
                    // and would otherwise drop the tile under them mid-flight.
                    raisedTileId = tile.id
                    let id = tile.id
                    Task {
                        try? await Task.sleep(for: .milliseconds(320))
                        if raisedTileId == id { raisedTileId = nil }
                    }
                }

                // Board busy resolving a cascade: buffer the swipe and replay
                // it the moment the board settles, so fast play never hits a
                // dead zone. The drag usually never locked (onChanged bails
                // while animating), so fall back to the dominant axis.
                if viewModel.isAnimating, !viewModel.isGameOver, !viewModel.isPaused {
                    withAnimation(.bouncy(duration: 0.25)) {
                        dragOffsets = [:]
                    }
                    let axis = lockedAxis ?? (abs(t.width) > abs(t.height) ? .horizontal : .vertical)
                    let raw = axis == .horizontal ? t.width : t.height
                    let predicted = axis == .horizontal ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                    let flick = predicted * raw > 0 && abs(predicted) > tileSize * 0.9 && abs(raw) >= 8
                    guard abs(raw) >= tileSize * 0.35 || flick else { return }
                    let sign = raw >= 0 ? 1 : -1
                    viewModel.queueSwap(
                        tileId: tile.id,
                        dRow: axis == .vertical ? sign : 0,
                        dCol: axis == .horizontal ? sign : 0
                    )
                    return
                }

                // A sloppy tap can travel a few points and lock the axis; keep
                // treating anything under 8pt as a tap, springing the small
                // residual offset back.
                let travel = max(abs(t.width), abs(t.height))
                guard wasLocked, let axis = lockedAxis, travel >= 8 else {
                    withAnimation(.bouncy(duration: 0.25)) {
                        dragOffsets = [:]
                    }
                    if travel < 8 {
                        viewModel.tileTapped(tile)
                    }
                    return
                }

                let raw = axis == .horizontal ? t.width : t.height
                let sign = raw >= 0 ? 1 : -1
                let dRow = axis == .vertical ? sign : 0
                let dCol = axis == .horizontal ? sign : 0
                let nr = tile.row + dRow, nc = tile.col + dCol
                let hasNeighbor = nr >= 0 && nr < viewModel.engine.rows && nc >= 0 && nc < viewModel.engine.cols

                // A fast flick should commit even if the finger travelled less
                // than half a tile: project the gesture to its natural end
                // point, requiring matching direction and some real travel.
                let predicted = axis == .horizontal ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                let flick = predicted * raw > 0 && abs(predicted) > tileSize * 0.9 && abs(raw) > tileSize * 0.2

                if hasNeighbor && (abs(raw) > tileSize * 0.5 || flick) {
                    // Commit: the residual offset and the cell change animate
                    // together, so the tile slides into place with no jump.
                    // The rubber-band guarantees a real distance to cover here.
                    withAnimation(.spring(duration: 0.24, bounce: 0.25)) {
                        dragOffsets = [:]
                        viewModel.beginDragSwap(tile, dRow: dRow, dCol: dCol)
                    }
                } else {
                    // Cancel: spring back to rest.
                    withAnimation(.bouncy(duration: 0.25)) {
                        dragOffsets = [:]
                    }
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(verbatim: "\(viewModel.isGameOver ? viewModel.score : viewModel.bestScore)")
                    .font(.subheadline.bold())
                    .foregroundStyle(viewModel.isNewBest ? Palette.cream : textColor.opacity(0.5))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(viewModel.isNewBest ? palette.orangeRed : textColor.opacity(0.12), in: Capsule())
                    .animation(.easeOut(duration: 0.3), value: viewModel.isNewBest)
                if viewModel.isGameOver {
                    Text("Game Over")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(textColor)
                        .transition(.asymmetric(insertion: .push(from: .bottom), removal: .identity))
                } else {
                    RollingCounter(
                        value: viewModel.score,
                        font: .system(size: 44, weight: .heavy),
                        color: textColor
                    )
                    .transition(.asymmetric(insertion: .identity, removal: .push(from: .top)))
                }
            }
            .animation(.easeOut(duration: 0.4), value: viewModel.isGameOver)
            .padding(.top, 32)

            Spacer()

            GeometryReader { geo in
                let tileSize = geo.size.width / CGFloat(viewModel.engine.cols)
                let gridHeight = tileSize * CGFloat(viewModel.engine.rows)

                ZStack(alignment: .topLeading) {
                    ForEach(viewModel.engine.allTiles) { tile in
                        let extra = dragOffsets[tile.id] ?? .zero
                        let isDragging = dragTileId == tile.id
                        TileView(
                            tile: tile,
                            color: palette.color(for: tile.type),
                            isSelected: viewModel.selectedTile?.id == tile.id,
                            isHinted: viewModel.hintTileIds.contains(tile.id),
                            isBombFlashed: viewModel.bombFlashTiles.contains(tile.id),
                            isPaused: viewModel.isPaused,
                            isGameOver: viewModel.isGameOver,
                            size: tileSize
                        )
                        .scaleEffect(isDragging ? 1.07 : 1)
                        .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: 7, y: 4)
                        .animation(.snappy(duration: 0.18), value: isDragging)
                        .offset(
                            x: CGFloat(tile.col) * tileSize + extra.width,
                            y: CGFloat(tile.row) * tileSize + extra.height
                        )
                        .zIndex(zIndex(for: tile))
                        .transition(.identity)
                        .gesture(tileDragGesture(tile, tileSize: tileSize))
                    }
                    ForEach(viewModel.matchRipples) { ripple in
                        RippleView(size: tileSize, color: textColor)
                            .offset(
                                x: CGFloat(ripple.col) * tileSize,
                                y: CGFloat(ripple.row) * tileSize
                            )
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: gridHeight, alignment: .topLeading)
                .padding(.top, tileSize)
                .clipped()
                .padding(.top, -tileSize)
                .overlay {
                    if viewModel.showNoMoves {
                        Text("No moves left!\nShuffling...")
                            .font(.title2.bold())
                            .foregroundStyle(textColor)
                            .multilineTextAlignment(.center)
                            .padding(24)
                            .background(bgColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.showNoMoves)
                .onChange(of: viewModel.isGameOver) {
                    if viewModel.isGameOver {
                        leaderboardId = UUID()
                        if viewModel.playerName.isEmpty {
                            leaderboardProfileMode = 1
                            showLeaderboard = true
                        } else {
                            leaderboardProfileMode = 0
                            Task {
                                await viewModel.submitScore()
                                showLeaderboard = true
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
                .overlay {
                    if viewModel.isPaused && !viewModel.isGameOver {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.togglePause()
                            }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Spacer()

            RoundedRectangle(cornerRadius: 3)
                .fill(isUrgent && !viewModel.isPaused ? palette.orangeRed.opacity(0.15) : textColor.opacity(0.15))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { barGeo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isUrgent && !viewModel.isPaused ? palette.orangeRed : textColor)
                            .frame(width: barGeo.size.width * (barFillAnimating ? min(viewModel.timeRemaining / 60, 1.0) : 0))
                    }
                }
                .clipped()
                .padding(.horizontal, 12)
                .animation(.linear(duration: 0.2), value: viewModel.timeRemaining)
                .animation(.easeOut(duration: 0.3), value: isUrgent)
                .overlay {
                    if isUrgent && !viewModel.isPaused {
                        Text("\(Int(viewModel.timeRemaining))")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(bgColor)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.3), value: Int(viewModel.timeRemaining))
                            .padding(16)
                            .background(palette.orangeRed, in: Circle())
                            .keyframeAnimator(initialValue: CGFloat(1.0), trigger: Int(viewModel.timeRemaining)) { content, scale in
                                content.scaleEffect(scale)
                            } keyframes: { _ in
                                SpringKeyframe(1.15, duration: 0.15, spring: .bouncy)
                                SpringKeyframe(1.0, duration: 0.3, spring: .smooth)
                            }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.3), value: isUrgent)
                .overlay(alignment: .top) {
                    if viewModel.isPaused {
                        Text("paused")
                            .font(.caption.smallCaps())
                            .foregroundStyle(textColor.opacity(0.5))
                            .offset(y: -28)
                            .transition(.opacity)
                    } else if showPauseHint {
                        Text("tap to pause")
                            .font(.caption.smallCaps())
                            .foregroundStyle(textColor.opacity(0.5))
                            .offset(y: -28)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.5), value: viewModel.isPaused)
                .animation(.easeOut(duration: 0.5), value: showPauseHint)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.hasStarted && !viewModel.isGameOver {
                    viewModel.togglePause()
                }
            }
            .onChange(of: viewModel.hasStarted) {
                if viewModel.hasStarted {
                    withAnimation(.easeOut(duration: 0.4)) {
                        barFillAnimating = true
                    }
                    showPauseHint = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showPauseHint = false
                    }
                } else {
                    barFillAnimating = false
                    showPauseHint = false
                }
            }

            Spacer()

            if viewModel.hasStarted && !viewModel.isPaused {
                Button { withAnimation { viewModel.setupGrid() } } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title)
                        .foregroundStyle(textColor)
                        .frame(width: 44, height: 44)
                }
                .padding(.bottom, 32)
            } else if viewModel.isPaused {
                Button {
                    leaderboardId = UUID()
                    leaderboardProfileMode = 0
                    showLeaderboard = true
                } label: {
                    Image(systemName: "star")
                        .font(.title)
                        .foregroundStyle(textColor)
                        .frame(width: 44, height: 44)
                }
                .padding(.bottom, 32)
            } else {
                Button {
                    leaderboardId = UUID()
                    leaderboardProfileMode = 0
                    showLeaderboard = true
                } label: {
                    Image(systemName: "star")
                        .font(.title)
                        .foregroundStyle(textColor)
                        .frame(width: 44, height: 44)
                }
                .padding(.bottom, 32)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor.ignoresSafeArea())
        .sheet(isPresented: $showLeaderboard, onDismiss: {
            if viewModel.isGameOver && !viewModel.playerName.isEmpty && !viewModel.scoreSubmitted {
                Task { await viewModel.submitScore() }
            }
        }) {
            LeaderboardView(
                playerName: Binding(
                    get: { viewModel.playerName },
                    set: { viewModel.playerName = $0 }
                ),
                playerLink: Binding(
                    get: { viewModel.playerLink },
                    set: { viewModel.playerLink = $0 }
                ),
                startTab: leaderboardProfileMode,
                highlightPlayerName: viewModel.isGameOver && viewModel.isNewBest && !viewModel.playerName.isEmpty ? viewModel.playerName : nil,
                onSave: {
                    if viewModel.isGameOver && !viewModel.scoreSubmitted {
                        await viewModel.submitScore()
                    }
                }
            )
            .id(leaderboardId)
            .preferredColorScheme(palette.appearanceMode.colorScheme)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if viewModel.hasStarted && !viewModel.isGameOver && !viewModel.isPaused {
                viewModel.togglePause()
            }
        }
    }
}

// Single discreet halo at the centroid of a matched group: a thin ring that
// expands and fades out.
private struct RippleView: View {
    let size: CGFloat
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.4), lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(animate ? 1.55 : 0.7)
            .opacity(animate ? 0 : 0.45)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { animate = true }
            }
    }
}
