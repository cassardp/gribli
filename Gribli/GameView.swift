import SwiftUI

struct GameView: View {
    var onBack: (() -> Void)?
    @State private var viewModel: GameViewModel

    @State private var barFillAnimating = false
    @State private var showLeaderboard = false
    @State private var leaderboardProfileMode = 0

    @Environment(\.colorScheme) private var colorScheme
    private var bgColor: Color { colorScheme == .dark ? Color(white: 0.1) : .white }
    private var textColor: Color { colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.2) }
    private var isUrgent: Bool { viewModel.timeRemaining <= 10 && viewModel.timeRemaining > 0 && viewModel.hasStarted && !viewModel.isGameOver }

    init(onBack: (() -> Void)? = nil) {
        self.onBack = onBack
        _viewModel = State(initialValue: GameViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(viewModel.isGameOver ? viewModel.score : viewModel.bestScore)")
                        .font(.body.bold())
                        .foregroundStyle(textColor.opacity(0.4))
                        .contentTransition(.numericText())
                    if viewModel.isNewBest {
                        Text("TOP")
                            .font(.caption2.bold())
                            .foregroundStyle(bgColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(textColor, in: Capsule())
                    }
                }
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
                            color: viewModel.color(for: tile.type),
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
            }
            .aspectRatio(1, contentMode: .fit)

            Spacer()

            RoundedRectangle(cornerRadius: 3)
                .fill(isUrgent && !viewModel.isPaused ? .red.opacity(0.15) : textColor.opacity(0.15))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { barGeo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isUrgent && !viewModel.isPaused ? .red : textColor)
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
                            .font(.title.monospacedDigit().bold())
                            .foregroundStyle(.red)
                            .phaseAnimator([false, true], trigger: Int(viewModel.timeRemaining)) { content, pulse in
                                content.scaleEffect(pulse ? 1.2 : 1.0)
                            } animation: { _ in
                                .easeInOut(duration: 0.4)
                            }
                            .padding(20)
                            .background(bgColor.opacity(0.4), in: Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.3), value: isUrgent)
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
                } else {
                    barFillAnimating = false
                }
            }

            Spacer()

            if viewModel.hasStarted {
                Button { withAnimation { viewModel.setupGrid() } } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundStyle(textColor)
                }
                .padding(.bottom, 32)
            } else {
                Button {
                    leaderboardProfileMode = 0
                    showLeaderboard = true
                } label: {
                    Image(systemName: "star")
                        .font(.title)
                        .foregroundStyle(textColor)
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
                onSave: {
                    if viewModel.isGameOver && !viewModel.scoreSubmitted {
                        await viewModel.submitScore()
                    }
                }
            )
        }
    }
}
