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
    private var flushWorkItem: DispatchWorkItem?
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
        flushWorkItem?.cancel()
        flushWorkItem = nil
        backingEntries.removeAll(keepingCapacity: true)
        if !entries.isEmpty {
            entries.removeAll(keepingCapacity: true)
        }
        if totalCount != 0 {
            totalCount = 0
        }
    }

    private func scheduleFlush() {
        guard flushWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.flushNow()
        }
        flushWorkItem = item
        let delay: TimeInterval = isExpanded ? 0.14 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func flushNow() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        if totalCount != backingEntries.count {
            totalCount = backingEntries.count
        }
        if isExpanded && entries != backingEntries {
            entries = backingEntries
        }
    }
}
