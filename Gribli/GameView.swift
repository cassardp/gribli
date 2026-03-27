import SwiftUI

struct GameView: View {
    @State private var viewModel: GameViewModel

    @State private var barFillAnimating = false
    @State private var showLeaderboard = false
    @State private var leaderboardProfileMode = 0
    @State private var leaderboardId = UUID()
    @State private var showPauseHint = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PaletteStore.self) private var palette
    private var bgColor: Color { Palette.background(for: colorScheme) }
    private var textColor: Color { Palette.text(for: colorScheme) }
    private var isUrgent: Bool { viewModel.timeRemaining <= 10 && viewModel.timeRemaining > 0 && viewModel.hasStarted && !viewModel.isGameOver }

    init() {
        _viewModel = State(initialValue: GameViewModel())
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
                        TileView(
                            tile: tile,
                            color: palette.color(for: tile.type),
                            isSelected: viewModel.selectedTile?.id == tile.id,
                            isBombFlashed: viewModel.bombFlashTiles.contains(tile.id),
                            isPaused: viewModel.isPaused,
                            isGameOver: viewModel.isGameOver,
                            size: tileSize
                        )
                        .offset(
                            x: CGFloat(tile.col) * tileSize,
                            y: CGFloat(tile.row) * tileSize
                        )
                        .transition(.identity)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    if max(abs(dx), abs(dy)) < 6 {
                                        viewModel.tileTapped(tile)
                                    } else if max(abs(dx), abs(dy)) >= 15 {
                                        if abs(dx) > abs(dy) {
                                            viewModel.tileSwiped(tile, dRow: 0, dCol: dx > 0 ? 1 : -1)
                                        } else {
                                            viewModel.tileSwiped(tile, dRow: dy > 0 ? 1 : -1, dCol: 0)
                                        }
                                    }
                                }
                        )
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
