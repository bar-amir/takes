import Foundation

/// One JSON line per run in ~/Library/Logs/Takes/runs.jsonl, for comparing timings later. Metadata only, and capped:
/// past `maxBytes` the oldest lines are dropped.
enum RunLog {
    static let url: URL = {
        // Tests and `--snapshot` renders never write to the user's log folder.
        let dir =
            Store.runningTests || Store.readOnly
            ? FileManager.default.temporaryDirectory.appendingPathComponent("takes-logs-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("runs.jsonl")
    }()

    /// About 2,000 runs. Past this the log is cut back to its newest half, so it isn't rewritten at every run.
    static let maxBytes = 512 * 1024
    /// A text value longer than this isn't metadata (a model name, an app's bundle ID and an engine are far shorter).
    static let maxValueLength = 120
    /// The only keys a line may carry: what `PanelModel`, `InstantMode` and `Bench` log. A new one is added here on
    /// purpose, so a value that holds the user's text can't get in under a new name.
    static let allowedKeys: Set<String> = ["kind", "model", "effort", "takes", "engine", "wallMs", "firstTextMs", "app"]

    static func append(_ entry: [String: Any], to file: URL = RunLog.url) {
        // `--snapshot` renders write nothing.
        guard !Store.readOnly else { return }
        var entry = metadata(entry)
        entry["at"] = ISO8601DateFormatter().string(from: Date())
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        // O_APPEND puts each line at the end, and the lock keeps the cut-back below from overlapping another writer:
        // `--bench` appends from a process of its own.
        let fd = open(file.path, O_RDWR | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        guard write(fd, line) else { return }
        if lseek(fd, 0, SEEK_END) > off_t(maxBytes) { cutBack(fd) }
    }

    /// Only the allowed keys, with numbers, flags and short text: a log line never carries a draft or a take.
    static func metadata(_ entry: [String: Any]) -> [String: Any] {
        entry.filter { key, value in
            guard allowedKeys.contains(key) else { return false }
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

    /// Rewrites the file, under the caller's lock, with only its newest half.
    private static func cutBack(_ fd: Int32) {
        lseek(fd, 0, SEEK_SET)
        guard let data = try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() else { return }
        guard ftruncate(fd, 0) == 0 else { return }
        _ = write(fd, newest(data, within: maxBytes / 2))
    }

    private static func write(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                if written < 0 { return false }
                offset += written
            }
            return true
        }
    }
}
