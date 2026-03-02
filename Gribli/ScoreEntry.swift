import Foundation

struct ScoreEntry: Codable, Identifiable {
    let id: Int
    let playerName: String
    let score: Int
    let link: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, score, link
        case playerName = "player_name"
        case createdAt = "created_at"
    }
}