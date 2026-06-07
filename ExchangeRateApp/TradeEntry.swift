import Foundation

struct TradeEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var pair: CurrencyPair
    var rate: Double        // raw API rate (per 1 unit)
    var baseAmount: Double? // foreign currency amount
    var note: String
}
