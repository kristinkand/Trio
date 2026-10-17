import Foundation

/// One thing the watch did or saw while untethered. A later version of the same `key` replaces an earlier one.
struct UntetheredRecord: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        /// LoopKit `NewPumpEvent.rawValue` as a binary property list.
        case pumpEvent(Data)
        /// A pending pump event the pump no longer reports (by sync identifier).
        case pumpEventDropped(String)
        case glucose(BloodGlucose)
        /// The reading at `date` was deleted on the watch.
        case glucoseDeleted(date: Date)
        case carbs(CarbsEntry)
        case carbsDeleted(id: String)
        case override(Override)
        /// Ends the override that started at `start`; one started later is left alone.
        case overrideEnded(start: Date)
        case tempTarget(TempTarget)
        /// Ends the temp target that started at `start`; one started later is left alone.
        case tempTargetEnded(start: Date)
        /// With its forecasts; `enactedAt` when the pump took it, nil for one that wasn't enacted.
        case determination(Determination, enactedAt: Date?)
        case tdd(UntetheredTDD)
        case autosens(Autosens)
        /// The watch's last completed loop; after the hand-back the phone counts its loop age from it.
        case loopCompleted(Date)
        /// The watch deactivated or discarded the pod: the phone forgets it when it takes the pump back.
        case podEnded(Date)
    }

    let key: String
    let id: UUID
    let date: Date
    let kind: Kind

    init(key: String, id: UUID = UUID(), date: Date, kind: Kind) {
        self.key = key
        self.id = id
        self.date = date
        self.kind = kind
    }

    var syncEntry: UntetheredSyncEntry { UntetheredSyncEntry(key: key, id: id, date: date) }

    /// The key for each kind of thing; versions of one thing share it.
    static func pumpEventKey(_ syncIdentifier: String) -> String { "pump:" + syncIdentifier }
    static func glucoseKey(_ date: Date) -> String { "bg:\(Int(date.timeIntervalSince1970))" }
    static func carbsKey(_ id: String) -> String { "carbs:" + id }
    static func overrideKey(_ start: Date) -> String { "override:\(Int(start.timeIntervalSince1970))" }
    static func tempTargetKey(_ start: Date) -> String { "tt:\(Int(start.timeIntervalSince1970))" }
    static func determinationKey(_ date: Date) -> String { "det:\(Int(date.timeIntervalSince1970))" }
    static func tddKey(_ date: Date) -> String { "tdd:\(Int(date.timeIntervalSince1970))" }
    static func autosensKey(_ date: Date) -> String { "autosens:\(Int(date.timeIntervalSince1970))" }
    /// One key: only the newest loop matters.
    static let loopCompletedKey = "loop"
    static let podEndedKey = "podEnded"
}

/// What both sides checksum: the latest version of each key, in 30-minute buckets by date.
struct UntetheredSyncEntry: Codable, Equatable {
    let key: String
    let id: UUID
    let date: Date

    var bucket: Int { UntetheredChecksum.bucket(of: date.timeIntervalSince1970) }

    static func bucketChecksums(of entries: [UntetheredSyncEntry]) -> [Int: Int] {
        var checksums: [Int: UntetheredChecksum] = [:]
        for entry in entries {
            checksums[entry.bucket, default: UntetheredChecksum()].add(fnv1a(entry.key), fnv1a(entry.id.uuidString))
        }
        return checksums.mapValues { Int(UInt32(truncatingIfNeeded: $0.transportValue)) }
    }

    /// Contiguous from the oldest bucket, 0 for an empty one.
    static func bucketChecksumList(of entries: [UntetheredSyncEntry]) -> (start: Int, checksums: [Int]) {
        let checksums = bucketChecksums(of: entries)
        guard let start = checksums.keys.min(), let end = checksums.keys.max() else { return (0, []) }
        return (start, (start ... end).map { checksums[$0] ?? 0 })
    }

    static func differingBuckets(local: [UntetheredSyncEntry], remoteStart: Int, remoteChecksums: [Int]) -> Set<Int> {
        let mine = bucketChecksums(of: local)
        let theirs = Dictionary(uniqueKeysWithValues: remoteChecksums.enumerated().map { (remoteStart + $0.offset, $0.element) })
        return Set(mine.keys).union(theirs.keys).filter { mine[$0] ?? 0 != theirs[$0] ?? 0 }
    }

    /// Stable across processes and devices, unlike `Hasher`.
    static func fnv1a(_ string: String) -> UInt64 {
        string.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}

/// Order-independent checksum over 30-minute buckets, so phone and watch compare their records bit for bit.
/// (The same checksum and bucket length the watch's glucose history sync uses upstream of this fork.)
struct UntetheredChecksum {
    static let bucketLength: TimeInterval = 30 * 60

    static func bucket(of timestamp: TimeInterval) -> Int {
        Int((timestamp / bucketLength).rounded(.down))
    }

    private(set) var count = 0
    private var sum: UInt64 = 0

    mutating func add(_ first: UInt64, _ second: UInt64) {
        count += 1
        sum &+= Self.mix(first ^ Self.mix(second))
    }

    /// Property lists only hold signed integers.
    var transportValue: Int64 { Int64(bitPattern: sum) }

    /// SplitMix64 finalizer: spreads every input bit over the whole result.
    private static func mix(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
