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

enum CurrencyPair: String, CaseIterable, Identifiable, Codable {
    case usdkrw = "USDKRW=X"
    case eurkrw = "EURKRW=X"
    case jpykrw = "JPYKRW=X"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usdkrw: return "USD"
        case .eurkrw: return "EUR"
        case .jpykrw: return "JPY"
        }
    }

    var headerText: String {
        switch self {
        case .usdkrw: return "USD / KRW"
        case .eurkrw: return "EUR / KRW"
        case .jpykrw: return "JPY / KRW"
        }
    }

    var symbol: String {
        switch self {
        case .usdkrw: return "$"
        case .eurkrw: return "€"
        case .jpykrw: return "¥"
        }
    }

    // JPY는 100엔 기준으로 표시
    var displayMultiplier: Double {
        switch self {
        case .jpykrw: return 100
        default:      return 1
        }
    }

    var displayUnitLabel: String {
        switch self {
        case .jpykrw: return "100 JPY"
        case .usdkrw: return "1 USD"
        case .eurkrw: return "1 EUR"
        }
    }

    var storageKey: String { "exchangeRate_\(rawValue)" }
}
