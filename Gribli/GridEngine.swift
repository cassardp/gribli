import Foundation

struct GridEngine {
    var grid: [[Tile]] = []
    let rows: Int
    let cols: Int

    var allTiles: [Tile] { grid.flatMap { $0 } }

    init(rows: Int = 8, cols: Int = 8) {
        self.rows = rows
        self.cols = cols
    }

    mutating func buildGrid() {
        grid = []
        for row in 0..<rows {
            var rowTiles: [Tile] = []
            for col in 0..<cols {
                let type = randomTypeAvoiding(row: row, col: col, currentRow: rowTiles)
                rowTiles.append(Tile(id: UUID(), type: type, row: row, col: col))
            }
            grid.append(rowTiles)
        }
    }

    private func randomTypeAvoiding(row: Int, col: Int, currentRow: [Tile]) -> TileType {
        let all = TileType.allCases
        var forbidden: Set<TileType> = []
        if col >= 2, currentRow[col - 1].type == currentRow[col - 2].type {
            forbidden.insert(currentRow[col - 1].type)
        }
        if row >= 2, grid[row - 1][col].type == grid[row - 2][col].type {
            forbidden.insert(grid[row - 1][col].type)
        }
        return all.filter { !forbidden.contains($0) }.randomElement()!
    }

    func isAdjacent(_ a: Tile, _ b: Tile) -> Bool {
        abs(a.row - b.row) + abs(a.col - b.col) == 1
    }

    mutating func swap(r1: Int, c1: Int, r2: Int, c2: Int) {
        grid[r1][c1].row = r2
        grid[r1][c1].col = c2
        grid[r2][c2].row = r1
        grid[r2][c2].col = c1
        let temp = grid[r1][c1]
        grid[r1][c1] = grid[r2][c2]
        grid[r2][c2] = temp
    }

    func findMatches() -> Set<UUID> {
        var matched = Set<UUID>()
        for row in 0..<rows {
            var col = 0
            while col < cols {
                let type = grid[row][col].type
                var end = col + 1
                while end < cols, grid[row][end].type == type { end += 1 }
                if end - col >= 3 {
                    for c in col..<end { matched.insert(grid[row][c].id) }
                }
                col = end
            }
        }
        for col in 0..<cols {
            var row = 0
            while row < rows {
                let type = grid[row][col].type
                var end = row + 1
                while end < rows, grid[end][col].type == type { end += 1 }
                if end - row >= 3 {
                    for r in row..<end { matched.insert(grid[r][col].id) }
                }
                row = end
            }
        }
        return matched
    }

    func expandBombsStaged(_ matches: Set<UUID>) -> (expanded: Set<UUID>, stages: [Set<UUID>]) {
        var expanded = matches
        var processed = Set<UUID>()
        var stages: [Set<UUID>] = []
        var changed = true
        while changed {
            changed = false
            for row in 0..<rows {
                for col in 0..<cols {
                    let tile = grid[row][col]
                    guard tile.isBomb, expanded.contains(tile.id), !processed.contains(tile.id) else { continue }
                    processed.insert(tile.id)
                    var bombArea = Set<UUID>()
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let r = row + dr, c = col + dc
                            guard r >= 0, r < rows, c >= 0, c < cols else { continue }
                            bombArea.insert(grid[r][c].id)
                            if expanded.insert(grid[r][c].id).inserted {
                                changed = true
                            }
                        }
                    }
                    stages.append(bombArea)
                }
            }
        }
        return (expanded, stages)
    }

    mutating func spawnBomb() {
        var newTiles: [(Int, Int)] = []
        for row in 0..<rows {
            for col in 0..<cols where grid[row][col].row < 0 {
                newTiles.append((row, col))
            }
        }
        guard let (r, c) = newTiles.randomElement() else { return }
        grid[r][c].isBomb = true
    }

    mutating func markMatched(_ matches: Set<UUID>) {
        for row in 0..<rows {
            for col in 0..<cols {
                if matches.contains(grid[row][col].id) {
                    grid[row][col].isMatched = true
                }
            }
        }
    }

    mutating func applyGravityAndSpawn() {
        for col in 0..<cols {
            var surviving: [Tile] = []
            for row in (0..<rows).reversed() {
                if !grid[row][col].isMatched {
                    surviving.append(grid[row][col])
                }
            }
            for i in 0..<surviving.count {
                let newRow = rows - 1 - i
                surviving[i].row = newRow
                surviving[i].col = col
                grid[newRow][col] = surviving[i]
            }
            let emptyCount = rows - surviving.count
            for i in 0..<emptyCount {
                grid[i][col] = Tile(
                    id: UUID(),
                    type: TileType.allCases.randomElement()!,
                    row: i - emptyCount,
                    col: col
                )
            }
        }
    }

    mutating func dropNewTiles() {
        for col in 0..<cols {
            for row in 0..<rows {
                if grid[row][col].row < 0 {
                    grid[row][col].row = row
                }
            }
        }
    }

    func findHint() -> (Int, Int, Int, Int)? {
        var types = grid.map { $0.map { $0.type } }
        func hasMatch(in t: [[TileType]]) -> Bool {
            for row in 0..<rows {
                var col = 0
                while col < cols {
                    let tp = t[row][col]
                    var end = col + 1
                    while end < cols, t[row][end] == tp { end += 1 }
                    if end - col >= 3 { return true }
                    col = end
                }
            }
            for col in 0..<cols {
                var row = 0
                while row < rows {
                    let tp = t[row][col]
                    var end = row + 1
                    while end < rows, t[end][col] == tp { end += 1 }
                    if end - row >= 3 { return true }
                    row = end
                }
            }
            return false
        }
        for row in 0..<rows {
            for col in 0..<cols {
                if col + 1 < cols {
                    types[row].swapAt(col, col + 1)
                    if hasMatch(in: types) { return (row, col, row, col + 1) }
                    types[row].swapAt(col, col + 1)
                }
                if row + 1 < rows {
                    let tmp = types[row][col]
                    types[row][col] = types[row + 1][col]
                    types[row + 1][col] = tmp
                    if hasMatch(in: types) { return (row, col, row + 1, col) }
                    types[row + 1][col] = types[row][col]
                    types[row][col] = tmp
                }
            }
        }
        return nil
    }

    func hasValidMoves() -> Bool {
        findHint() != nil
    }
}
