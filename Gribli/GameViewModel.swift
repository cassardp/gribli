import SwiftUI

enum TileType: CaseIterable {
    case olive, red, orange, blue, silver, taupe
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
    var hintTileIds: Set<UUID> = []

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)

    // A swipe issued while the board is still resolving; replayed as soon as
    // it settles. Keyed by tile id so it dies gracefully if the tile gets
    // matched away or the board is shuffled in the meantime.
    private var pendingSwap: (tileId: UUID, dRow: Int, dCol: Int)?
    private var hintTask: Task<Void, Never>?

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
        rigidHaptic.prepare()
    }

    deinit {
        timerTask?.cancel()
        hintTask?.cancel()
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
        pendingSwap = nil
        cancelHint()
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
                    cancelHint()
                }
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { cancelHint() } else { scheduleHint() }
    }

    // MARK: - Idle hint

    // After a few seconds without interaction, the two tiles of a valid swap
    // pulse gently. Any touch, swap, or cascade re-arms the timer.
    private func scheduleHint() {
        hintTask?.cancel()
        if !hintTileIds.isEmpty { hintTileIds = [] }
        guard hasStarted, !isGameOver, !isPaused else { return }
        hintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !isAnimating, !isGameOver, !isPaused else { return }
            if let (r1, c1, r2, c2) = engine.findHint() {
                hintTileIds = [engine.grid[r1][c1].id, engine.grid[r2][c2].id]
            }
        }
    }

    func cancelHint() {
        hintTask?.cancel()
        if !hintTileIds.isEmpty { hintTileIds = [] }
    }

    // Light tick when the drag crosses the commit threshold, so the swap feels
    // magnetically "snapped" into place.
    func swapThresholdHaptic() {
        if hapticsEnabled { lightHaptic.impactOccurred(intensity: 0.6) }
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
        scheduleHint()
    }

    func tileTapped(_ tile: Tile) {
        guard !isAnimating, !isGameOver, !isPaused else { return }
        if !hasStarted { startGame() }
        scheduleHint()
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
        cancelHint()
        let r1 = tile.row, c1 = tile.col
        let r2 = r1 + dRow, c2 = c1 + dCol
        guard r2 >= 0, r2 < engine.rows, c2 >= 0, c2 < engine.cols else { return }
        isAnimating = true
        selectedTile = nil
        engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
        // No beat here: the exchange already played out under the finger
        // (rubber-band + threshold tick), so any pause before the collapse
        // reads as dead time. The pop overlaps the short residual slide.
        Task { await resolveSwap(r1: r1, c1: c1, r2: r2, c2: c2, landDelay: 0) }
    }

    // Buffers a swipe issued while a cascade is still resolving. Last swipe
    // wins; a light tick acknowledges that the input registered.
    func queueSwap(tileId: UUID, dRow: Int, dCol: Int) {
        guard isAnimating, !isGameOver, !isPaused else { return }
        pendingSwap = (tileId, dRow, dCol)
        if hapticsEnabled { lightHaptic.impactOccurred(intensity: 0.35) }
    }

    private func flushPendingSwap() {
        guard let pending = pendingSwap else { return }
        pendingSwap = nil
        guard !isGameOver, !isPaused else { return }
        guard let tile = engine.allTiles.first(where: { $0.id == pending.tileId }) else { return }
        let r2 = tile.row + pending.dRow, c2 = tile.col + pending.dCol
        guard r2 >= 0, r2 < engine.rows, c2 >= 0, c2 < engine.cols else { return }
        let neighbor = engine.grid[r2][c2]
        Task { await trySwap(tile, neighbor) }
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

    private func resolveSwap(r1: Int, c1: Int, r2: Int, c2: Int, landDelay: Int = 140) async {
        if engine.findMatches().isEmpty {
            // No match: let the swap land fully, then revert with a clear
            // bouncy back-and-forth so the failed move reads as a refusal.
            // A single firm clack makes the "no" readable under the finger,
            // distinct from the light commit tick.
            try? await Task.sleep(for: .milliseconds(160))
            if hapticsEnabled { rigidHaptic.impactOccurred(intensity: 0.8) }
            withAnimation(.spring(duration: 0.34, bounce: 0.5)) {
                engine.swap(r1: r1, c1: c1, r2: r2, c2: c2)
            }
            try? await Task.sleep(for: .milliseconds(300))
            isAnimating = false
            flushPendingSwap()
            scheduleHint()
        } else {
            // Match: let the committed swap land before the collapse fires,
            // so the exchange and the match read as two beats. Drag swaps
            // pass a shorter beat than tap swaps (less distance left).
            try? await Task.sleep(for: .milliseconds(landDelay))
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
            engine.markMatched(matches)
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
        flushPendingSwap()
        scheduleHint()
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
