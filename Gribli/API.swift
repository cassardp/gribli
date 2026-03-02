import CryptoKit
import Foundation

enum APIError: Error {
    case nameTaken
    case serverError
}

enum API {
    static let base = URL(string: "https://gribli-api.cassard.workers.dev")!
    private static let hmacKey = SymmetricKey(data: Data(Secrets.hmacKey.utf8))

    static func submitScore(playerName: String, score: Int, link: String?,
                            deviceId: String) async throws {
        let body = try JSONEncoder().encode(ScorePayload(
            player_name: playerName, score: score,
            link: link, device_id: deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        ))
        let (_, response) = try await URLSession.shared.data(for: signed("POST", path: "scores", body: body))
        guard let http = response as? HTTPURLResponse else { throw APIError.serverError }
        if http.statusCode == 409 { throw APIError.nameTaken }
        guard 200...299 ~= http.statusCode else { throw APIError.serverError }
    }

    static func updateProfile(playerName: String, link: String?,
                              deviceId: String) async throws {
        let body = try JSONEncoder().encode(ProfilePayload(
            player_name: playerName, link: link,
            device_id: deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        ))
        let (_, response) = try await URLSession.shared.data(for: signed("PUT", path: "profile", body: body))
        guard let http = response as? HTTPURLResponse else { throw APIError.serverError }
        if http.statusCode == 409 { throw APIError.nameTaken }
        guard 200...299 ~= http.statusCode else { throw APIError.serverError }
    }

    static func loadScores() async throws -> [ScoreEntry] {
        let (data, response) = try await URLSession.shared.data(
            from: base.appending(path: "scores"))
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScoreEntry].self, from: data)
    }

    private static func signed(_ method: String, path: String, body: Data) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: hmacKey)
        request.setValue(mac.map { String(format: "%02x", $0) }.joined(), forHTTPHeaderField: "X-Signature")
        return request
    }
}

private struct ScorePayload: Encodable {
    let player_name: String
    let score: Int
    let link: String?
    let device_id: String
    let timestamp: Int64
}

private struct ProfilePayload: Encodable {
    let player_name: String
    let link: String?
    let device_id: String
    let timestamp: Int64
}
