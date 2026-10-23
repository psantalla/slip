import Foundation

enum Files {
    static func frame(for url: URL) -> (Header, Data)? {
        guard let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
              vals.isDirectory != true,
              let size = vals.fileSize, size <= Wire.maxPayload,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return (Header(kind: Kind.file, name: url.lastPathComponent, device: nil), data)
    }

    static func save(_ data: Data, name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "_")
        var url = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        while fm.fileExists(atPath: url.path) {
            let stem = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            url = dir.appendingPathComponent(stem); n += 1
        }
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }
}
