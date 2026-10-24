import Foundation

enum Settings {
    private static let d = UserDefaults.standard
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var code: String {
        get {
            if let c = d.string(forKey: "code"), !c.isEmpty { return c }
            let c = Self.newCode(); d.set(c, forKey: "code"); return c
        }
        set { d.set(newValue, forKey: "code") }
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Slip/config.json")
    }

    private static func config() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    static var saveDir: URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Slip", isDirectory: true)
        guard let p = config()["saveDir"] as? String, !p.isEmpty else { return fallback }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var role: String {
        get { d.string(forKey: "role") ?? "host" }
        set { d.set(newValue, forKey: "role") }
    }

    static var joinCode: String {
        get { d.string(forKey: "joinCode") ?? "" }
        set { d.set(newValue, forKey: "joinCode") }
    }

    static var otherSide: Side {
        get { Side(rawValue: UInt8(exactly: d.integer(forKey: "otherSide")) ?? 1) ?? .right }
        set { d.set(Int(newValue.rawValue), forKey: "otherSide") }
    }

    static var kvmOn: Bool {
        get { d.bool(forKey: "kvmOn") }
        set { d.set(newValue, forKey: "kvmOn") }
    }

    static var kvmAlign: Double {
        get { d.double(forKey: "kvmAlign") }
        set { d.set(newValue, forKey: "kvmAlign") }
    }

    static var clipOn: Bool {
        get { d.object(forKey: "clipOn") == nil ? true : d.bool(forKey: "clipOn") }
        set { d.set(newValue, forKey: "clipOn") }
    }

    static var filesOn: Bool {
        get { d.object(forKey: "filesOn") == nil ? true : d.bool(forKey: "filesOn") }
        set { d.set(newValue, forKey: "filesOn") }
    }

    static var deviceName: String { Host.current().localizedName ?? "Mac" }

    // logging, config.json: log (bool), logLevel (debug|info|warn|error), logMaxKB (int), logDir (path)
    static var logEnabled: Bool {
        if let v = config()["log"] as? Bool { return v }          // explicit wins
        return FileManager.default.fileExists(atPath: home.appendingPathComponent("LFL").path)   // default: on if sync folder present
    }
    static var logLevel: String { config()["logLevel"] as? String ?? "info" }
    static var logMaxKB: Int { max(16, config()["logMaxKB"] as? Int ?? 256) }
    static var logDir: URL {
        if let p = config()["logDir"] as? String, !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }
        let lfl = home.appendingPathComponent("LFL", isDirectory: true)   // sync folder if present, else standard location
        return FileManager.default.fileExists(atPath: lfl.path) ? lfl : home.appendingPathComponent("Library/Logs/Slip", isDirectory: true)
    }

    static func newCode() -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var rng = SystemRandomNumberGenerator()
        let s = (0..<10).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] }
        return String(s[0..<5]) + "-" + String(s[5..<10])
    }
}
