import Foundation

// Diagnostic log to ~/LFL/slip-<mac>.log (only if ~/LFL exists). Syncs across Macs for debugging.
enum Log {
    private static let queue = DispatchQueue(label: "slip.log")
    private static let url: URL? = {
        let lfl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("LFL", isDirectory: true)
        guard FileManager.default.fileExists(atPath: lfl.path) else { return nil }
        let name = (Host.current().localizedName ?? "mac").replacingOccurrences(of: " ", with: "_")
        return lfl.appendingPathComponent("slip-\(name).log")
    }()

    static func line(_ s: String) {
        guard let url else { return }
        queue.async {
            let t = ISO8601DateFormatter().string(from: Date())
            let msg = "\(t) \(s)\n"
            guard let data = msg.data(using: .utf8) else { return }
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile(); fh.write(data); try? fh.close()
            } else {
                try? msg.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
