//
//  Logging.swift
//  Sora
//
//  Created by seiike on 16/01/2025.
//

import Foundation

class Logger: @unchecked Sendable {
    static let shared = Logger()
    
    struct LogEntry {
        let message: String
        let type: String
        let timestamp: Date
    }
    
    private let queue = DispatchQueue(label: "me.cranci.sora.logger", attributes: .concurrent)
    private var logs: [LogEntry] = []
    private let maxLogEntries = 300
    private let logFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("persistent_logs.txt")
    }()
    private let logDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd-MM HH:mm:ss"
        return df
    }()
    
    private init() {
        loadPersistedLogs()
    }
    
    func log(_ message: String, type: String = "General") {
        let entry = LogEntry(message: message, type: type, timestamp: Date())
        
        queue.async(flags: .barrier) {
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogEntries {
                self.logs.removeFirst(self.logs.count - self.maxLogEntries)
            }

            self.debugLog(entry)
            self.appendEntryToFile(entry)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("LoggerNotification"), object: nil,
                                                userInfo: [
                                                    "message": message,
                                                    "type": type,
                                                    "timestamp": entry.timestamp
                                                ]
                )
            }
        }
    }
    
    func getLogs() -> String {
        var result = ""
        queue.sync {
            result = logs.map { "[\(logDateFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)" }
                .joined(separator: "\n----\n")
        }
        return result
    }
    
    func getLogsAsync() async -> String {
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = self.logs.map { "[\(self.logDateFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)" }
                    .joined(separator: "\n")
                continuation.resume(returning: result)
            }
        }
    }
    
    func exportLogsToFile() async -> URL? {
        return await withCheckedContinuation { continuation in
            queue.async {
                self.flushLogsToDiskIfNeeded()
                continuation.resume(returning: self.logFileURL)
            }
        }
    }
    
    func clearLogs() {
        queue.async(flags: .barrier) {
            self.logs.removeAll()
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
    }
    
    func clearLogsAsync() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.logs.removeAll()
                try? FileManager.default.removeItem(at: self.logFileURL)
                continuation.resume()
            }
        }
    }
    
    private func debugLog(_ entry: LogEntry) {
#if DEBUG
        let formattedMessage = "[\(logDateFormatter.string(from: entry.timestamp))] [\(entry.type)] \(entry.message)"
        print(formattedMessage)
#endif
    }

    private func appendEntryToFile(_ entry: LogEntry) {
        let line = "[\(logDateFormatter.string(from: entry.timestamp))] [\(entry.type)] \(entry.message)\n"
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                } catch {
                    // swallow
                }
            }
        } else {
            try? line.data(using: .utf8)?.write(to: logFileURL)
        }
    }

    private func loadPersistedLogs() {
        guard let data = try? Data(contentsOf: logFileURL), let content = String(data: data, encoding: .utf8) else { return }
        var loaded: [LogEntry] = []
        content.split(separator: "\n").forEach { line in
            let text = String(line)
            if let entry = parseLine(text) {
                loaded.append(entry)
            }
        }
        // keep only most recent in memory, but file stays intact
        if loaded.count > maxLogEntries {
            loaded = Array(loaded.suffix(maxLogEntries))
        }
        logs = loaded
    }

    private func parseLine(_ line: String) -> LogEntry? {
        let pattern = #"\[(.+?)\] \[(.+?)\] (.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }

        let tsRange = Range(match.range(at: 1), in: line)
        let typeRange = Range(match.range(at: 2), in: line)
        let msgRange = Range(match.range(at: 3), in: line)

        guard let tsRange, let typeRange, let msgRange,
              let date = logDateFormatter.date(from: String(line[tsRange])) else { return nil }
        let type = String(line[typeRange])
        let msg = String(line[msgRange])
        return LogEntry(message: msg, type: type, timestamp: date)
    }

    private func flushLogsToDiskIfNeeded() {
        // ensure file exists; no-op if already written during log
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            let content = logs.map { "[\(logDateFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)" }.joined(separator: "\n")
            try? content.data(using: .utf8)?.write(to: logFileURL)
        }
    }
}
