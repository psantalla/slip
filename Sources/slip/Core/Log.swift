import Foundation

enum LogLevel: Int, Comparable {
    case debug, info, warn, error
    init(_ s: String) {
        switch s.lowercased() {
        case "debug": self = .debug
        case "warn", "warning": self = .warn
        case "error": self = .error
        default: self = .info
        }
    }
    var tag: String { ["DBG", "INF", "WRN", "ERR"][rawValue] }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

// self-trimming: capped, keeps newest
enum Log {
    private static let queue = DispatchQueue(label: "slip.log")
    private static let dateFmt = ISO8601DateFormatter()
    private static let threshold = LogLevel(Settings.logLevel)
    private static let maxBytes = Settings.logMaxKB * 1024
    private static let keepBytes = maxBytes / 4
    private static let url: URL? = {
        guard Settings.logEnabled else { return nil }
        let dir = Settings.logDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (Host.current().localizedName ?? "mac").replacingOccurrences(of: " ", with: "_")
        return dir.appendingPathComponent("slip-\(name).log")
    }()

    static func debug(_ s: @autoclosure () -> String) { emit(.debug, s) }
    static func line(_ s: @autoclosure () -> String) { emit(.info, s) }
    static func info(_ s: @autoclosure () -> String) { emit(.info, s) }
    static func warn(_ s: @autoclosure () -> String) { emit(.warn, s) }
    static func error(_ s: @autoclosure () -> String) { emit(.error, s) }

    private static func emit(_ level: LogLevel, _ s: () -> String) {
        guard let url, level >= threshold else { return }
        let msg = s()
        queue.async {
            let t = dateFmt.string(from: Date())
            guard let data = "\(t) \(level.tag) \(msg)\n".data(using: .utf8) else { return }
            guard let fh = try? FileHandle(forWritingTo: url) else { try? data.write(to: url); return }
            if fh.seekToEndOfFile() > maxBytes {
                try? fh.close()
                trimTail(url)
                if let fh2 = try? FileHandle(forWritingTo: url) { fh2.seekToEndOfFile(); fh2.write(data); try? fh2.close() }
            } else {
                fh.write(data); try? fh.close()
            }
        }
    }

    // drop leading partial line
    private static func trimTail(_ url: URL) {
        guard let all = try? Data(contentsOf: url), all.count > keepBytes else { return }
        var tail = Data(all.suffix(keepBytes))
        if let nl = tail.firstIndex(of: 0x0A), nl + 1 < tail.count { tail = Data(tail[(nl + 1)...]) }
        try? tail.write(to: url, options: .atomic)
    }
}
