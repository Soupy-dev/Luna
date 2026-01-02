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
    private let maxLogEntries = 1000
    
    private init() {}
    
    func log(_ message: String, type: String = "General") {
        let entry = LogEntry(message: message, type: type, timestamp: Date())
        
        queue.async(flags: .barrier) {
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogEntries {
                self.logs.removeFirst(self.logs.count - self.maxLogEntries)
            }

            self.debugLog(entry)
            
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
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd-MM HH:mm:ss"
            result = logs.map { "[\(dateFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)" }
                .joined(separator: "\n----\n")
        }
        return result
    }
    
    func getLogsAsync() async -> String {
        return await withCheckedContinuation { continuation in
            queue.async {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MM HH:mm:ss"
                let result = self.logs.map { "[\(dateFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)" }
                    .joined(separator: "\n")
                continuation.resume(returning: result)
            }
        }
    }
    
    func exportLogsToFile() async -> URL? {
        let logsContent = await getLogsAsync()
        let fileName = "Luna_Logs_\(DateFormatter().string(from: Date())).txt"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try logsContent.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            print("Failed to export logs: \(error)")
            return nil
        }
    }
    
    func clearLogs() {
        queue.async(flags: .barrier) {
            self.logs.removeAll()
        }
    }
    
    func clearLogsAsync() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.logs.removeAll()
                continuation.resume()
            }
        }
    }
    
    private func debugLog(_ entry: LogEntry) {
#if DEBUG
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM HH:mm:ss"
        let formattedMessage = "[\(dateFormatter.string(from: entry.timestamp))] [\(entry.type)] \(entry.message)"
        print(formattedMessage)
#endif
    }
}
