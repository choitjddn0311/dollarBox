import WidgetKit
import Foundation

struct ExchangeRateEntry: TimelineEntry {
    let date: Date
    let exchangeRate: ExchangeRate?
    let chartData: [RateDataPoint]
}

struct ExchangeRateProvider: TimelineProvider {

    func placeholder(in context: Context) -> ExchangeRateEntry {
        ExchangeRateEntry(date: Date(), exchangeRate: ExchangeRate(rate: 1558.84, previousClose: 1542.10, updatedAt: Date()), chartData: previewData())
    }

    func getSnapshot(in context: Context, completion: @escaping (ExchangeRateEntry) -> Void) {
        let rate = ExchangeRateService.shared.loadRate() ?? ExchangeRate(rate: 1558.84, previousClose: nil, updatedAt: Date())
        completion(ExchangeRateEntry(date: Date(), exchangeRate: rate, chartData: previewData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExchangeRateEntry>) -> Void) {
        Task {
            // FX_DAILY 한 번 호출로 차트 데이터 + 최신 종가 동시에 확보
            let history = (try? await ExchangeRateService.shared.fetchHistory(for: .week)) ?? []
            let rate = history.last.map { ExchangeRate(rate: $0.rate, previousClose: nil, updatedAt: $0.date) }
                ?? ExchangeRateService.shared.loadRate()

            let entry = ExchangeRateEntry(date: Date(), exchangeRate: rate, chartData: history)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func previewData() -> [RateDataPoint] {
        let values = [1520.0, 1515.0, 1530.0, 1525.0, 1540.0, 1535.0, 1558.0]
        return values.enumerated().map { i, rate in
            let date = Calendar.current.date(byAdding: .day, value: i - 6, to: Date())!
            return RateDataPoint(date: date, rate: rate)
        }
    }
}
