import SwiftUI

enum TileType: String, CaseIterable {
    case apple = "🍏"
    case cherry = "🍒"
    case lemon = "🍋"
    case grape = "🍇"
    case coconut = "🥥"
    case peach = "🍑"
}

enum PopupKind {
    case score
}

struct ScorePopup: Identifiable {
    let id = UUID()
    let text: String
    let kind: PopupKind
    var chain: Int = 1
}

struct Tile: Identifiable, Equatable {
    let id: UUID
    var type: TileType
    var row: Int
    var col: Int
    var isMatched = false
    var isBomb = false
}

@Observable
class GameViewModel {
    var engine = GridEngine()
    var score = 0
    var selectedTile: Tile?
    var isAnimating = false
    var showNoMoves = false
    var bombFlashTiles: Set<UUID> = []
    var bestScore: Int {
        didSet { UserDefaults.standard.set(bestScore, forKey: "bestScore") }
    }
    var isNewBest = false
    var scorePopups: [ScorePopup] = []
    var timeRemaining: Double = 60
    var isGameOver = false
    var hasStarted = false
    var isPaused = false
    var timerTask: Task<Void, Never>?
    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    var playerName: String {
        didSet { UserDefaults.standard.set(playerName, forKey: "playerName") }
    }
    var playerLink: String {
        didSet { UserDefaults.standard.set(playerLink, forKey: "playerLink") }
    }
    var scoreSubmitted = false

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    private var timerStart: Date?
    private var timerBudget: Double = 60

    init() {
        self.bestScore = UserDefaults.standard.integer(forKey: "bestScore")
        self.hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
        self.playerName = UserDefaults.standard.string(forKey: "playerName") ?? ""
        self.playerLink = UserDefaults.standard.string(forKey: "playerLink") ?? ""
        setupGrid()
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
    }

    deinit {
        timerTask?.cancel()
    }

    func color(for type: TileType) -> Color {
        switch type {
        case .apple: Color(red: 0.18, green: 0.76, blue: 0.35)
        case .cherry: Color(red: 0.92, green: 0.24, blue: 0.28)
        case .lemon: Color(red: 0.98, green: 0.80, blue: 0.0)
        case .grape: Color(red: 0.56, green: 0.28, blue: 0.86)
        case .coconut: Color(red: 0.20, green: 0.56, blue: 0.96)
        case .peach: Color(red: 0.98, green: 0.52, blue: 0.12)
        }
    }

    func setupGrid() {
        score = 0
        selectedTile = nil
        isAnimating = false
        isNewBest = false
        isGameOver = false
        scoreSubmitted = false
        hasStarted = false
        isPaused = false
        timerTask?.cancel()
        scorePopups.removeAll()
        engine.buildGrid()
        timeRemaining = 30
    }

    private func startTimer() {
        timerTask?.cancel()
        timerStart = Date.now
        timerBudget = timeRemaining
        timerTask = Task { @MainActor in
            while !Task.isCancelled && timeRemaining > 0 {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                if isPaused {
                    timerStart = Date.now
                    timerBudget = timeRemaining
                    continue
                }
                let elapsed = Date.now.timeIntervalSince(timerStart!)
                timeRemaining = max(0, timerBudget - elapsed)
                if timeRemaining <= 0 {
                    isGameOver = true
                }
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
    }

    private func showPopup(_ text: String, kind: PopupKind, chain: Int = 1) {
        let popup = ScorePopup(text: text, kind: kind, chain: chain)
        withAnimation(.spring(duration: 0.3)) {
            scorePopups.append(popup)
        }
        let popupId = popup.id
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation { scorePopups.removeAll { $0.id == popupId } }
        }
    }

    func addTime(matchCount: Int, chain: Int, hasBomb: Bool) {
        let base: Double = timeRemaining <= 10 ? 1.5 : 0.5
        var bonus: Double = base + Double(max(0, matchCount - 3)) * 0.5
        if chain > 1 { bonus += Double(chain - 1) * 1.0 }
        if hasBomb { bonus += 1 }
        timeRemaining = min(60, timeRemaining + bonus)
        resyncTimer()
    }

    private func resyncTimer() {
        timerStart = Date.now
        timerBudget = timeRemaining
    }

    func startGame() {
        hasStarted = true
        startTimer()
    }

    func tileTapped(_ tile: Tile) {
        guard !isAnimating, !isGameOver, !isPaused else { return }
        if !hasStarted { startGame() }
        if let selected = selectedTile {
            if selected.id == tile.id {
                selectedTile = nil
            } else if engine.isAdjacent(selected, tile) {
                selectedTile = nil
                Task { await trySwap(selected, tile) }
            } else {
                selectedTile = tile
            }
        } else {
            selectedTile = tile
        }
    }

    func tileSwiped(_ tile: Tile, dRow: Int, dCol: Int) {
        guard !isAnimating, !isGameOver, !isPaused else { return }
        if !hasStarted { startGame() }
        let newRow = tile.row + dRow
        let newCol = tile.col + dCol
        guard newRow >= 0, newRow < engine.rows, newCol >= 0, newCol < engine.cols else { return }
        selectedTile = tile
        let neighbor = engine.grid[newRow][newCol]
        Task { await trySwap(tile, neighbor) }
    }

    // MARK: - Swap

    private func trySwap(_ a: Tile, _ b: Tile) async {
        isAnimating = true
        let r1 = a.row, c1 = a.col, r2 = b.row, c2 = b.col

        withAnimation(.spring(duration: 0.25)) {
            engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
        }
        try? await Task.sleep(for: .milliseconds(220))
        selectedTile = nil

        if engine.findMatches().isEmpty {
            withAnimation(.spring(duration: 0.3)) {
                engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
            }
            try? await Task.sleep(for: .milliseconds(300))
            isAnimating = false
        } else {
            await processCascade()
        }
    }

    // MARK: - Cascade

    private func processCascade() async {
        var chain = 1
        while true {
            let rawMatches = engine.findMatches()
            if rawMatches.isEmpty { break }

            let hasBomb = engine.grid.lazy.flatMap({ $0 }).contains { $0.isBomb && rawMatches.contains($0.id) }
            let matches: Set<UUID>
            if hasBomb {
                let (expanded, stages) = engine.expandBombsStaged(rawMatches)
                matches = expanded
                for stage in stages {
                    withAnimation(.easeOut(duration: 0.08)) {
                        bombFlashTiles = stage
                    }
                    if hapticsEnabled { heavyHaptic.impactOccurred(intensity: 1.0) }
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeOut(duration: 0.1)) {
                        bombFlashTiles = []
                    }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            } else {
                matches = rawMatches
            }

            withAnimation(.easeOut(duration: 0.18)) {
                engine.markMatched(matches)
            }
            if hapticsEnabled {
                let intensity = min(1.0, 0.5 + Double(chain) * 0.15)
                if hasBomb {
                    Task {
                        mediumHaptic.impactOccurred(intensity: 0.7)
                        try? await Task.sleep(for: .milliseconds(60))
                        mediumHaptic.impactOccurred(intensity: 0.4)
                        try? await Task.sleep(for: .milliseconds(50))
                        lightHaptic.impactOccurred(intensity: 0.3)
                    }
                } else if chain <= 2 {
                    lightHaptic.impactOccurred(intensity: intensity)
                } else {
                    mediumHaptic.impactOccurred(intensity: intensity)
                }
            }
            let points = matches.count * 10 * chain
            score += points
            if score > bestScore {
                bestScore = score
                isNewBest = true
            }
            addTime(matchCount: rawMatches.count, chain: chain, hasBomb: hasBomb)
            showPopup("+\(points)", kind: .score, chain: chain)
            chain += 1

            try? await Task.sleep(for: .milliseconds(150))

            withAnimation(.spring(duration: 0.25)) {
                engine.applyGravityAndSpawn()
            }
            if chain >= 4 { engine.spawnBomb() }
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.spring(duration: 0.25)) {
                engine.dropNewTiles()
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        if !engine.hasValidMoves() {
            showNoMoves = true
            try? await Task.sleep(for: .milliseconds(1200))
            showNoMoves = false
            withAnimation { engine.buildGrid() }
        }
        isAnimating = false
    }

    func submitScore() async {
        guard !scoreSubmitted, !playerName.isEmpty, score > 0 else { return }
        scoreSubmitted = true
        _ = try? await API.submitScore(
            playerName: playerName,
            score: score,
            link: playerLink.isEmpty ? nil : playerLink,
            deviceId: deviceId
        )
    }
}
