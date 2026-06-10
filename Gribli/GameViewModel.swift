import SwiftUI

enum TileType: CaseIterable {
    case olive, red, orange, blue, silver, taupe
}

struct MatchRipple: Identifiable {
    let id = UUID()
    let row: Double
    let col: Double
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
    var matchRipples: [MatchRipple] = []
    var timeRemaining: Double = 30
    var isGameOver = false
    var hasStarted = false
    var isPaused = false
    var timerTask: Task<Void, Never>?
    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    var playerName: String {
        didSet {
            let clean = String(playerName.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression).prefix(20))
            if clean != playerName { playerName = clean }
            UserDefaults.standard.set(playerName, forKey: "playerName")
        }
    }
    var playerLink: String {
        didSet { UserDefaults.standard.set(playerLink, forKey: "playerLink") }
    }
    var scoreSubmitted = false

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    private var timerStart: Date?
    private var timerBudget: Double = 30

    init() {
        self.bestScore = UserDefaults.standard.integer(forKey: "bestScore")
        self.hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
        let rawName = UserDefaults.standard.string(forKey: "playerName") ?? ""
        self.playerName = String(rawName.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression).prefix(20))
        self.playerLink = UserDefaults.standard.string(forKey: "playerLink") ?? ""
        setupGrid()
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
    }

    deinit {
        timerTask?.cancel()
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
        matchRipples.removeAll()
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

    // Light tick when the drag crosses the commit threshold, so the swap feels
    // magnetically "snapped" into place.
    func swapThresholdHaptic() {
        if hapticsEnabled { lightHaptic.impactOccurred(intensity: 0.6) }
    }

    private func matchCentroid(_ matches: Set<UUID>) -> (row: Double, col: Double)? {
        var sumRow = 0.0, sumCol = 0.0, count = 0.0
        for r in 0..<engine.rows {
            for c in 0..<engine.cols where matches.contains(engine.grid[r][c].id) {
                sumRow += Double(r)
                sumCol += Double(c)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (sumRow / count, sumCol / count)
    }

    // Spawns a single expanding shockwave at the centroid of a matched group.
    private func emitRipple(at center: (row: Double, col: Double)) {
        let ripple = MatchRipple(row: center.row, col: center.col)
        matchRipples.append(ripple)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            matchRipples.removeAll { $0.id == ripple.id }
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

    // Commits a swap that the user already dragged into place. The caller wraps
    // this in its own `withAnimation` so the residual drag offset and the cell
    // change animate together — no visual jump at release.
    func beginDragSwap(_ tile: Tile, dRow: Int, dCol: Int) {
        guard !isAnimating, !isGameOver, !isPaused else { return }
        if !hasStarted { startGame() }
        let r1 = tile.row, c1 = tile.col
        let r2 = r1 + dRow, c2 = c1 + dCol
        guard r2 >= 0, r2 < engine.rows, c2 >= 0, c2 < engine.cols else { return }
        isAnimating = true
        selectedTile = nil
        engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
        Task { await resolveSwap(r1: r1, c1: c1, r2: r2, c2: c2) }
    }

    // MARK: - Swap

    private func trySwap(_ a: Tile, _ b: Tile) async {
        isAnimating = true
        let r1 = a.row, c1 = a.col, r2 = b.row, c2 = b.col

        withAnimation(.spring(duration: 0.25, bounce: 0.35)) {
            engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
        }
        selectedTile = nil
        await resolveSwap(r1: r1, c1: c1, r2: r2, c2: c2)
    }

    private func resolveSwap(r1: Int, c1: Int, r2: Int, c2: Int) async {
        if engine.findMatches().isEmpty {
            // No match: let the swap land fully, then revert with a clear
            // bouncy back-and-forth so the failed move reads as a refusal.
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(duration: 0.34, bounce: 0.5)) {
                engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
            }
            try? await Task.sleep(for: .milliseconds(300))
            isAnimating = false
        } else {
            // Match: let the committed swap land (~0.24s spring) before the
            // collapse fires, so the exchange and the match read as two beats.
            try? await Task.sleep(for: .milliseconds(170))
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

            // The bloom/collapse pop is driven by a keyframe animator in TileView,
            // keyed on `isMatched`, so this is just a plain state flip.
            let center = matchCentroid(matches)
            engine.markMatched(matches)
            if let center { emitRipple(at: center) }
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
            chain += 1

            // Let the collapse (~0.2s) complete before gravity yanks the
            // matched tiles out — otherwise it gets cut mid-animation.
            try? await Task.sleep(for: .milliseconds(200))

            // The fall itself is nearly bounce-free: the landing impact is sold
            // by the squash & stretch keyframes in TileView, keyed on `row`.
            withAnimation(.spring(duration: 0.3, bounce: 0.08)) {
                engine.applyGravityAndSpawn()
            }
            if chain >= 4 { engine.spawnBomb() }
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.spring(duration: 0.3, bounce: 0.08)) {
                engine.dropNewTiles()
            }
            try? await Task.sleep(for: .milliseconds(120))
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
            score: max(score, bestScore),
            link: playerLink.isEmpty ? nil : playerLink,
            deviceId: deviceId
        )
    }
}
