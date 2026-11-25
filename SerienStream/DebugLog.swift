import Foundation

/// In-App-Logging mit Ringpuffer — sichtbar in Settings → Diagnose.
/// Zusätzlich in eine Datei im Documents-Ordner, damit CI/Tests sie auslesen können.
final class DebugLog {
    static let shared = DebugLog()

    private var entries: [String] = []
    private let maxEntries = 500
    private let lock = NSLock()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug.log")
    }

    func log(_ message: String, category: String = "app") {
        let line = "\(dateFormatter.string(from: Date())) [\(category)] \(message)"
        lock.lock()
        entries.append(line)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
        print(line)
        // Append ins File (best effort)
        if let data = (line + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    func all() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func clear() {
        lock.lock()
        entries = []
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

func DLog(_ message: String, category: String = "app") {
    DebugLog.shared.log(message, category: category)
}
