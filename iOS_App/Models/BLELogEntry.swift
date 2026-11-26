import Foundation
import Combine

/// Entrée du journal de débogage BLE (émissions, réceptions, informations et erreurs).
struct BLELogEntry: Identifiable, Equatable {
    enum Direction: String {
        case tx = "TX"
        case rx = "RX"
        case info = "INFO"
        case error = "ERR"
    }

    let id: UUID
    let timestamp: Date
    let direction: Direction
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), direction: Direction, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.message = message
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }

    var prefixSymbol: String {
        switch direction {
        case .tx: return "→"
        case .rx: return "←"
        case .info: return "•"
        case .error: return "!"
        }
    }
}

/// Magasin de logs optimisé : regroupement des publications UI et trim par lots (O(1) amorti).
final class BLELogStore: ObservableObject {
    @Published private(set) var entries: [BLELogEntry] = []
    @Published private(set) var totalCount: Int = 0

    private var backingEntries: [BLELogEntry] = []
    private var isExpanded: Bool = false
    private var flushScheduled: Bool = false
    private let maxEntries: Int
    private let trimSlack = 40

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
        self.backingEntries.reserveCapacity(maxEntries + trimSlack)
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        if expanded {
            flushNow()
        }
    }

    func append(_ direction: BLELogEntry.Direction, _ message: String) {
        backingEntries.append(BLELogEntry(direction: direction, message: message))
        if backingEntries.count > maxEntries + trimSlack {
            backingEntries.removeFirst(backingEntries.count - maxEntries)
        }

        if direction == .error {
            flushNow()
        } else {
            scheduleFlush()
        }
    }

    func clear() {
        backingEntries.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
        totalCount = 0
        flushScheduled = false
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.flushNow()
        }
    }

    private func flushNow() {
        flushScheduled = false
        if totalCount != backingEntries.count {
            totalCount = backingEntries.count
        }
        if isExpanded {
            entries = backingEntries
        }
    }
}
