import Foundation

let deviceId: String = {
    let key = "deviceId"
    if let existing = UserDefaults.standard.string(forKey: key) { return existing }
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: key)
    return id
}()
