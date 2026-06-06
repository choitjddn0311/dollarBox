import Foundation

struct RateDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let rate: Double
}

enum RatePeriod: String, CaseIterable, Identifiable {
    case week = "1W"
    case month = "1M"
    case year = "1Y"
    var id: String { rawValue }
}
