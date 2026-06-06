import SwiftUI
import Charts
import WidgetKit

struct ExchangeRateWidgetView: View {
    let entry: ExchangeRateEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        case .systemLarge:  largeView
        default:            smallView
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USD/KRW")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let rate = entry.exchangeRate?.rate {
                Text(rate, format: .number.precision(.fractionLength(0)))
                    .font(.title2.bold())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            if let updatedAt = entry.exchangeRate?.updatedAt {
                Text(updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            sparklineChart
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            // 좌측: 환율 정보
            VStack(alignment: .leading, spacing: 4) {
                Text("USD/KRW")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let rate = entry.exchangeRate?.rate {
                    Text(rate, format: .number.precision(.fractionLength(2)))
                        .font(.title3.bold())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }

                Spacer()

                if let updatedAt = entry.exchangeRate?.updatedAt {
                    Text(updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110)

            // 우측: 차트
            miniChart
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Large

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 상단: 환율
            VStack(alignment: .leading, spacing: 2) {
                Text("USD / KRW")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let rate = entry.exchangeRate?.rate {
                    Text(rate, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }

                if let updatedAt = entry.exchangeRate?.updatedAt {
                    Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 하단: 풀 차트
            fullChart
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Chart Views

    private var sparklineChart: some View {
        Group {
            if entry.chartData.isEmpty {
                Color.clear
            } else {
                Chart(entry.chartData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", chartYDomain.lowerBound),
                        yEnd: .value("Rate", point.rate)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Rate", point.rate)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: chartYDomain)
            }
        }
    }

    private var miniChart: some View {
        Group {
            if entry.chartData.isEmpty {
                Color.clear
            } else {
                Chart(entry.chartData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", chartYDomain.lowerBound),
                        yEnd: .value("Rate", point.rate)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Rate", point.rate)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: chartYDomain)
            }
        }
    }

    private var fullChart: some View {
        Group {
            if entry.chartData.isEmpty {
                Color.clear
            } else {
                Chart(entry.chartData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", chartYDomain.lowerBound),
                        yEnd: .value("Rate", point.rate)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Rate", point.rate)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v, format: .number.precision(.fractionLength(0)))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: chartYDomain)
            }
        }
    }

    // MARK: - Helpers

    private var chartYDomain: ClosedRange<Double> {
        let rates = entry.chartData.map { $0.rate }
        guard let lo = rates.min(), let hi = rates.max(), lo < hi else {
            return 1500...1600
        }
        let pad = (hi - lo) * 0.25
        return (lo - pad)...(hi + pad)
    }
}

#Preview(as: .systemSmall) {
    ExchangeRateWidget()
} timeline: {
    ExchangeRateEntry(
        date: .now,
        exchangeRate: ExchangeRate(rate: 1558.84, updatedAt: .now),
        chartData: sampleData()
    )
}

#Preview(as: .systemMedium) {
    ExchangeRateWidget()
} timeline: {
    ExchangeRateEntry(
        date: .now,
        exchangeRate: ExchangeRate(rate: 1558.84, updatedAt: .now),
        chartData: sampleData()
    )
}

#Preview(as: .systemLarge) {
    ExchangeRateWidget()
} timeline: {
    ExchangeRateEntry(
        date: .now,
        exchangeRate: ExchangeRate(rate: 1558.84, updatedAt: .now),
        chartData: sampleData()
    )
}

private func sampleData() -> [RateDataPoint] {
    let values = [1520.0, 1515.0, 1530.0, 1525.0, 1540.0, 1535.0, 1558.0]
    return values.enumerated().map { i, rate in
        let date = Calendar.current.date(byAdding: .day, value: i - 6, to: Date())!
        return RateDataPoint(date: date, rate: rate)
    }
}
