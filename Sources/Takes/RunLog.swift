import Foundation

/// One JSON line per run in ~/Library/Logs/Takes/runs.jsonl, for comparing timings later. Metadata only, and capped:
/// past `maxBytes` the oldest lines are dropped.
enum RunLog {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("runs.jsonl")
    }()

    /// About 2,000 runs. Past this the log is cut back to its newest half, so it isn't rewritten at every run.
    static let maxBytes = 512 * 1024
    /// A text value longer than this isn't metadata (a model name, an app's bundle ID and an engine are far shorter).
    static let maxValueLength = 120

    private static let lock = NSLock()

    static func append(_ entry: [String: Any], to file: URL = RunLog.url) {
        // `--snapshot` renders write nothing.
        guard !Store.readOnly else { return }
        var entry = metadata(entry)
        entry["at"] = ISO8601DateFormatter().string(from: Date())
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        var size = line.count
        if let handle = try? FileHandle(forWritingTo: file) {
            size += Int(handle.seekToEndOfFile())
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
        if size > maxBytes, let data = try? Data(contentsOf: file) {
            try? newest(data, within: maxBytes / 2).write(to: file, options: .atomic)
        }
    }

    /// Only numbers, flags and short text: a log line never carries a draft or a take, whatever a caller passes.
    static func metadata(_ entry: [String: Any]) -> [String: Any] {
        entry.filter { _, value in
            switch value {
            case is Bool, is Int, is Double, is NSNumber: return true
            case let text as String: return text.count <= maxValueLength
            default: return false
            }
        }
    }

    /// The last whole lines of `data` that fit in `limit` bytes.
    static func newest(_ data: Data, within limit: Int) -> Data {
        guard data.count > limit else { return data }
        var tail = data.suffix(limit)
        // Unless the cut fell right after a line break, the first line is partial: drop it.
        if data[data.count - limit - 1] != 0x0A {
            guard let newline = tail.firstIndex(of: 0x0A) else { return Data() }
            tail = tail[(newline + 1)...]
        }
        return Data(tail)
    }
}
