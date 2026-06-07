import Foundation

struct ExchangeRate: Codable {
    let rate: Double
    let previousClose: Double?
    let updatedAt: Date

    var change: Double? {
        guard let prev = previousClose else { return nil }
        return rate - prev
    }

    var changePercent: Double? {
        guard let prev = previousClose, prev > 0 else { return nil }
        return ((rate - prev) / prev) * 100
    }
}
