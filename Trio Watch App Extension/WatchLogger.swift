import Foundation
import os
import WatchConnectivity

final class WatchLogger: Sendable {
    static let shared = WatchLogger()

    fileprivate struct PendingDrafts {
        var drafts: [WatchLogDraft] = []
        var flushScheduled = false
    }

    private static let flushDelay: Duration = .seconds(5)
    private static let flushCount = 50
    private static let bufferLimit = 2000
    private static let shipInterval: Duration = .seconds(5 * 60)

    private let pending = OSAllocatedUnfairLock(initialState: PendingDrafts())
    private let shipper = WatchLogShipper()
    private let throttle = OSAllocatedUnfairLock(initialState: [String: (state: String, date: Date)]())
    private let osLoggers: [WatchLogEntry.Category: os.Logger] = {
        let subsystem = Bundle.main.bundleIdentifier ?? "Trio Watch"
        return Dictionary(uniqueKeysWithValues: WatchLogEntry.Category.allCases.map {
            ($0, os.Logger(subsystem: subsystem, category: $0.name))
        })
    }()

    private init() {
        Task { [shipper, pending] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.shipInterval)
                await shipper.drain(pending)
                await shipper.ship(onRequest: false)
            }
        }
    }

    func debug(_ category: WatchLogEntry.Category, _ message: String) {
        log(.debug, category, message)
    }

    func info(_ category: WatchLogEntry.Category, _ message: String) {
        log(.info, category, message)
    }

    func warning(_ category: WatchLogEntry.Category, _ message: String, error: Error? = nil) {
        log(.warning, category, Self.message(message, error: error))
    }

    func error(_ category: WatchLogEntry.Category, _ message: String, error: Error? = nil) {
        log(.error, category, Self.message(message, error: error))
    }

    // At most one line per key and interval while the state stays the same
    func shouldLog(_ key: String, state: String = "", every interval: TimeInterval = 30) -> Bool {
        let now = Date()
        return throttle.withLock { last in
            if let previous = last[key], previous.state == state, now.timeIntervalSince(previous.date) < interval {
                return false
            }
            last[key] = (state, now)
            return true
        }
    }

    func didEnterBackground() {
        Task { [shipper, pending] in
            await shipper.drain(pending)
            await shipper.ship(onRequest: false)
        }
    }

    // Requests and acks from the phone; returns false for unrelated messages
    func handlePhoneMessage(_ message: [String: Any]) -> Bool {
        if let ack = message[WatchLogTransfer.ack] as? NSNumber {
            let installID = message[WatchLogTransfer.installID] as? String
            Task { [shipper] in await shipper.acknowledge(ack.uint64Value, installID: installID) }
            return true
        }
        if message[WatchLogTransfer.request] as? Bool == true {
            Task { [shipper, pending] in
                await shipper.drain(pending)
                await shipper.ship(onRequest: true)
            }
            return true
        }
        return false
    }

    func transferFinished(_ transfer: WCSessionFileTransfer, error: Error?) {
        guard let metadata = transfer.file.metadata, metadata[WatchLogTransfer.marker] != nil else { return }
        let url = transfer.file.fileURL
        let firstSeq = (metadata[WatchLogTransfer.firstSeq] as? NSNumber)?.uint64Value ?? 1
        if let error {
            warning(.connectivity, "Log transfer to the phone failed, will retry", error: error)
        }
        Task { [shipper] in await shipper.finished(url, firstSeq: firstSeq, failed: error != nil) }
    }

    private func log(_ level: WatchLogEntry.Level, _ category: WatchLogEntry.Category, _ message: String) {
        osLoggers[category]?.log(level: level.osLogType, "\(message, privacy: .public)")
        let draft = WatchLogDraft(date: Date(), level: level, category: category, message: message)
        let (flushNow, scheduleDelayed) = pending.withLock { state -> (Bool, Bool) in
            state.drafts.append(draft)
            if state.drafts.count > Self.bufferLimit {
                state.drafts.removeFirst(state.drafts.count - Self.bufferLimit)
            }
            let scheduleDelayed = !state.flushScheduled
            state.flushScheduled = true
            return (state.drafts.count >= Self.flushCount, scheduleDelayed)
        }
        if flushNow {
            Task { [shipper, pending] in await shipper.drain(pending) }
        } else if scheduleDelayed {
            Task { [shipper, pending] in
                try? await Task.sleep(for: Self.flushDelay)
                await shipper.drain(pending)
            }
        }
    }

    private static func message(_ message: String, error: Error?) -> String {
        guard let error else { return message }
        let nsError = error as NSError
        return "\(message) (\(nsError.domain) \(nsError.code): \(nsError.localizedDescription))"
    }
}

private actor WatchLogShipper {
    private static let staleTransfer: TimeInterval = 30 * 60
    private static let osLog = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Trio Watch", category: "WatchLog")

    private var ring: WatchLogRing?
    // Highest seq handed to a file transfer; falls back to the ack on failure or relaunch
    private var sentSeq: UInt64 = 0

    private let outbox = WatchLogRing.defaultDirectory.deletingLastPathComponent()
        .appendingPathComponent("WatchLogOutbox", isDirectory: true)

    private func openRing() -> WatchLogRing {
        if let ring { return ring }
        let ring = WatchLogRing()
        ring.prune()
        self.ring = ring
        sentSeq = ring.ackedSeq
        clearOutbox()
        return ring
    }

    func drain(_ pending: OSAllocatedUnfairLock<WatchLogger.PendingDrafts>) {
        let drafts = pending.withLock { state -> [WatchLogDraft] in
            defer {
                state.drafts.removeAll(keepingCapacity: true)
                state.flushScheduled = false
            }
            return state.drafts
        }
        guard !drafts.isEmpty else { return }
        let ring = openRing()
        ring.append(drafts)
        ring.prune()
    }

    func ship(onRequest: Bool) {
        let ring = openRing()
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }

        let outstanding = session.outstandingFileTransfers.filter { $0.file.metadata?[WatchLogTransfer.marker] != nil }
        let cutoff = Date().timeIntervalSince1970 - Self.staleTransfer
        let stale = outstanding.filter { ($0.file.metadata?[WatchLogTransfer.created] as? TimeInterval ?? 0) < cutoff }
        if !stale.isEmpty {
            stale.forEach { $0.cancel() }
            sentSeq = ring.ackedSeq
        } else if !outstanding.isEmpty, !onRequest {
            return
        }

        // A request resends everything unacknowledged so a lost earlier batch can't leave a gap
        let from = onRequest ? ring.ackedSeq : max(ring.ackedSeq, sentSeq)
        guard ring.lastSeq > from else { return }
        let entries = ring.entries(after: from)
        guard let first = entries.first, let last = entries.last else { return }

        let url = outbox.appendingPathComponent("\(first.seq)-\(last.seq).jsonl")
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            try WatchLogEntry.jsonLines(entries).write(to: url, options: .atomic)
        } catch {
            Self.osLog.error("Writing watch log batch failed: \(String(describing: error), privacy: .public)")
            return
        }
        let metadata: [String: Any] = [
            WatchLogTransfer.marker: WatchLogTransfer.version,
            WatchLogTransfer.firstSeq: NSNumber(value: first.seq),
            WatchLogTransfer.lastSeq: NSNumber(value: last.seq),
            WatchLogTransfer.watchBuild: Self.build,
            WatchLogTransfer.installID: ring.installID,
            WatchLogTransfer.created: Date().timeIntervalSince1970
        ]
        session.transferFile(url, metadata: metadata)
        sentSeq = last.seq
        Self.osLog.debug("Queued watch log entries \(first.seq)-\(last.seq) for transfer")
    }

    func finished(_ url: URL, firstSeq: UInt64, failed: Bool) {
        try? FileManager.default.removeItem(at: url)
        if failed {
            sentSeq = min(sentSeq, firstSeq - 1)
        }
    }

    func acknowledge(_ seq: UInt64, installID: String?) {
        let ring = openRing()
        guard installID == ring.installID else { return }
        ring.acknowledge(seq)
        sentSeq = max(sentSeq, ring.ackedSeq)
    }

    // Batches left over from an earlier launch are rebuilt from the ring
    private func clearOutbox() {
        let inFlight = Set(WCSession.default.outstandingFileTransfers.map(\.file.fileURL.lastPathComponent))
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        for file in files where !inFlight.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static let build: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()
}

private extension WatchLogEntry.Level {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}

// MARK: - Untethered mode's lines

/// Untethered mode and the watch's own G7 reader write plain lines (`log`). They go to the phone as before the
/// structured log, as text (`UntetheredLineLog`), which the phone files under Watch/Legacy: on 27 October the
/// structured log's file transfers brought one line in a hundred of theirs, and none of the lines that would have
/// said why the watch didn't start by itself.
extension WatchLogger {
    func log(
        _ message: String,
        force: Bool = false,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) async {
        await UntetheredLineLog.shared.log(message, force: force, function: function, file: file, line: line)
    }

    /// Sends what was kept back while the phone was away; `queued` hands it to WatchConnectivity's queue even with the
    /// phone in reach. The structured log goes with it.
    func flushPersistedLogs(queued: Bool = false) async {
        await UntetheredLineLog.shared.flushPersistedLogs(queued: queued)
        didEnterBackground()
    }
}

/// The watch log as it was sent before the structured log: kept in memory, sent every 3 minutes or 100 lines, and kept
/// in a file while the phone is away, sent once it is back.
actor UntetheredLineLog {
    static let shared = UntetheredLineLog()

    private var logs: [String] = []
    private let maxEntries = 500
    private let flushInterval: TimeInterval = 3 * 60
    private let flushSizeThreshold = 100
    private var lastFlush = Date()

    private let session = WCSession.default
    private var timerTask: Task<Void, Never>?

    private init() {
        Task {
            await startFlushTimer()
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }

    private func startFlushTimer() async {
        timerTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
                await flushIfNeeded(force: false)
            }
        }
    }

    func log(
        _ message: String,
        force: Bool = false,
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) async {
        let shortFile = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(shortFile):\(line)] \(function) → \(message)"

        logs.append(entry)
        if logs.count > maxEntries {
            logs.removeFirst(logs.count - maxEntries)
        }

        print(entry)
        await flushIfNeeded(force: force)
    }

    func flushIfNeeded(force: Bool = false) async {
        let now = Date()
        let shouldFlush = force || now.timeIntervalSince(lastFlush) >= flushInterval || logs.count >= flushSizeThreshold

        if shouldFlush {
            await flushToPhone()
        }
    }

    private func flushToPhone() async {
        guard !logs.isEmpty else {
            return
        }

        let payload: [String: Any] = ["watchLogs": logs.joined(separator: "\n")]

        if session.activationState != .activated {
            session.activate()
        }

        if session.isReachable {
            // the buffer is empty by the time a send fails: what failed is kept, not the empty buffer
            let sent = logs
            session.sendMessage(payload, replyHandler: nil) { _ in
                Task {
                    await self.persistLogsLocally(sent)
                }
            }
        } else {
            await persistLogsLocally()
        }

        lastFlush = Date()
        logs.removeAll()
    }

    func persistLogsLocally(_ entries: [String]? = nil) async {
        let logDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("logs", isDirectory: true)

        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let logFile = logDir.appendingPathComponent("watch_log.txt")
        let previousLogFile = logDir.appendingPathComponent("watch_log_prev.txt")
        let startOfDay = Calendar.current.startOfDay(for: Date())

        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let creationDate = attributes[.creationDate] as? Date,
           creationDate < startOfDay
        {
            try? FileManager.default.removeItem(at: previousLogFile)
            try? FileManager.default.moveItem(at: logFile, to: previousLogFile)
            FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: [.creationDate: startOfDay])
        }

        let fullLog = (entries ?? logs).joined(separator: "\n") + "\n"
        if let data = fullLog.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                try? handle.seekToEnd()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    /// `queued` hands the log to WatchConnectivity even with the phone reachable: a log kept back while the
    /// phone was away can be too large for an interactive message.
    func flushPersistedLogs(queued: Bool = false) async {
        let logDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("logs", isDirectory: true)
        // Yesterday's file first: what was kept back before midnight moves there at the first line after it and was
        // never sent (25 October: the watch log from 21:31 to midnight, an untethered night with the phone away).
        await flushPersistedLog(at: logDir.appendingPathComponent("watch_log_prev.txt"), queued: queued)
        await flushPersistedLog(at: logDir.appendingPathComponent("watch_log.txt"), queued: queued)
    }

    private func flushPersistedLog(at logFile: URL, queued: Bool) async {
        guard let data = try? Data(contentsOf: logFile),
              let logString = String(data: data, encoding: .utf8),
              !logString.isEmpty
        else { return }

        if session.activationState != .activated {
            session.activate()
        }

        // hours kept back while the phone was away are far over what one transfer takes ("payload too large"): in
        // parts, each of which the phone appends
        for part in Self.parts(of: logString) {
            let payload: [String: Any] = ["watchLogs": part]
            if session.isReachable, !queued {
                session.sendMessage(payload, replyHandler: nil) { _ in
                    Task {
                        await self.persistLogsLocally(part.split(separator: "\n").map(String.init))
                    }
                }
            } else {
                _ = session.transferUserInfo(payload)
            }
        }
        try? FileManager.default.removeItem(at: logFile)
    }

    /// WatchConnectivity refuses a payload a little over 64 KB; whole lines, at most `maxBytes` each part.
    static func parts(of log: String, maxBytes: Int = 48000) -> [String] {
        var parts: [String] = []
        var current = ""
        var size = 0
        for line in log.split(separator: "\n") {
            let lineSize = line.utf8.count + 1
            if size > 0, size + lineSize > maxBytes {
                parts.append(current)
                current = ""
                size = 0
            }
            current += line + "\n"
            size += lineSize
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
