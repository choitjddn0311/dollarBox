import Foundation

// storageKey는 CurrencyPair.storageKey 로 대체

// MARK: - Yahoo Finance Response

private struct YahooFinanceResponse: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [Result]?
    }

    struct Result: Decodable {
        let meta: Meta
        let timestamp: [TimeInterval]?
        let indicators: Indicators?
    }

    struct Meta: Decodable {
        let regularMarketPrice: Double
        let chartPreviousClose: Double?
    }

    struct Indicators: Decodable {
        let quote: [Quote]?
    }

    struct Quote: Decodable {
        let close: [Double?]?
    }
}

// MARK: - Service

final class ExchangeRateService {
    static let shared = ExchangeRateService()
    private init() {}

    private var historyCache: [CurrencyPair: [RatePeriod: (data: [RateDataPoint], fetchedAt: Date)]] = [:]
    private let cacheTTL: TimeInterval = 30 * 60

    // MARK: Current Rate

    func fetchLatestRate(pair: CurrencyPair = .usdkrw) async throws -> ExchangeRate {
        let result = try await fetchYahoo(ticker: pair.rawValue, range: "1d", interval: "1m")
        return ExchangeRate(
            rate: result.meta.regularMarketPrice,
            previousClose: result.meta.chartPreviousClose,
            updatedAt: Date()
        )
    }

    // MARK: History

    func fetchHistory(for period: RatePeriod, pair: CurrencyPair = .usdkrw) async throws -> [RateDataPoint] {
        if let cached = historyCache[pair]?[period],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.data
        }

        let range: String
        switch period {
        case .week:  range = "5d"
        case .month: range = "1mo"
        case .year:  range = "1y"
        }

        let result = try await fetchYahoo(ticker: pair.rawValue, range: range, interval: "1d")
        let points = parseHistory(from: result)

        if historyCache[pair] == nil { historyCache[pair] = [:] }
        historyCache[pair]?[period] = (data: points, fetchedAt: Date())
        return points
    }

    // MARK: Core Fetch

    private func fetchYahoo(ticker: String, range: String, interval: String) async throws -> YahooFinanceResponse.Result {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)")!
        components.queryItems = [
            .init(name: "interval", value: interval),
            .init(name: "range", value: range)
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(YahooFinanceResponse.self, from: data)
        guard let result = decoded.chart.result?.first else {
            throw URLError(.cannotParseResponse)
        }
        return result
    }

    private func parseHistory(from result: YahooFinanceResponse.Result) -> [RateDataPoint] {
        guard
            let timestamps = result.timestamp,
            let closes = result.indicators?.quote?.first?.close
        else { return [] }

        return zip(timestamps, closes)
            .compactMap { ts, close -> RateDataPoint? in
                guard let close else { return nil }
                return RateDataPoint(date: Date(timeIntervalSince1970: ts), rate: close)
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: Storage

    func clearCache() {
        historyCache.removeAll()
    }

    func saveRate(_ exchangeRate: ExchangeRate, pair: CurrencyPair = .usdkrw) {
        guard let data = try? JSONEncoder().encode(exchangeRate) else { return }
        UserDefaults.standard.set(data, forKey: pair.storageKey)
    }

    func loadRate(pair: CurrencyPair = .usdkrw) -> ExchangeRate? {
        guard
            let data = UserDefaults.standard.data(forKey: pair.storageKey),
            let rate = try? JSONDecoder().decode(ExchangeRate.self, from: data)
        else { return nil }
        return rate
    }
}
