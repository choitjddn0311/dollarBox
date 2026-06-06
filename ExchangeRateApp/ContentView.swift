import SwiftUI
import Charts
import WidgetKit

struct ContentView: View {
    @AppStorage("themeMode") private var themeMode: String = "system"

    @State private var exchangeRate: ExchangeRate?
    @State private var history: [RateDataPoint] = []
    @State private var selectedPeriod: RatePeriod = .week
    @State private var isLoadingRate = false
    @State private var isLoadingChart = false
    @State private var selectedPoint: RateDataPoint? = nil

    private var preferredScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private var themeIcon: String {
        switch themeMode {
        case "light": return "sun.max"
        case "dark":  return "moon"
        default:      return "circle.lefthalf.filled"
        }
    }

    private var minPoint: RateDataPoint? { history.min(by: { $0.rate < $1.rate }) }
    private var maxPoint: RateDataPoint? { history.max(by: { $0.rate < $1.rate }) }

    private var yDomain: ClosedRange<Double> {
        guard let lo = minPoint?.rate, let hi = maxPoint?.rate, lo < hi else {
            return 1500...1600
        }
        let pad = (hi - lo) * 0.35
        return (lo - pad)...(hi + pad)
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedPeriod {
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day().month(.abbreviated)
        case .year:  return .dateTime.month(.abbreviated)
        }
    }

    private var displayedRate: Double? { selectedPoint?.rate ?? exchangeRate?.rate }
    private var displayedDate: Date?   { selectedPoint?.date ?? exchangeRate?.updatedAt }
    private var isDragging: Bool       { selectedPoint != nil }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 14) {
                ratePanel
                chartPanel
            }
            .padding(20)
        }
        .frame(minWidth: 700, minHeight: 540)
        .preferredColorScheme(preferredScheme)
        .task { await loadAll() }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.10, blue: 0.26),
                Color(red: 0.10, green: 0.04, blue: 0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Rate Panel

    private var ratePanel: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("USD / KRW")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .leading) {
                    if isLoadingRate {
                        ProgressView()
                            .scaleEffect(1.1)
                            .frame(height: 66)
                    } else {
                        Text(displayedRate.map {
                            $0.formatted(.number.precision(.fractionLength(2)))
                        } ?? "--")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(isDragging ? Color.accentColor : .primary)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)
                    }
                }
                .frame(height: 66)

                if let date = displayedDate {
                    Text(isDragging
                         ? date.formatted(date: .abbreviated, time: .omitted)
                         : "Updated \(date.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(isDragging ? Color.accentColor : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Menu {
                    Button { themeMode = "light" } label: {
                        Label("라이트", systemImage: "sun.max")
                    }
                    Button { themeMode = "dark" } label: {
                        Label("다크", systemImage: "moon")
                    }
                    Button { themeMode = "system" } label: {
                        Label("시스템", systemImage: "circle.lefthalf.filled")
                    }
                } label: {
                    Image(systemName: themeIcon)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassEffect(in: Circle())

                Button {
                    Task { await loadAll(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 38, height: 38)
                        .rotationEffect(isLoadingRate || isLoadingChart ? .degrees(360) : .zero)
                        .animation(
                            isLoadingRate || isLoadingChart
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: isLoadingRate || isLoadingChart
                        )
                }
                .buttonStyle(.plain)
                .glassEffect(in: Circle())
                .disabled(isLoadingRate || isLoadingChart)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Chart Panel

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            periodPicker
            chartArea
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("기간", selection: $selectedPeriod) {
            ForEach(RatePeriod.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .onChange(of: selectedPeriod) { _, _ in
            selectedPoint = nil
            Task { await loadHistory() }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartArea: some View {
        if isLoadingChart {
            ProgressView("불러오는 중...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if history.isEmpty {
            Text("데이터를 불러올 수 없습니다")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(history) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", yDomain.lowerBound),
                        yEnd: .value("Rate", point.rate)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.25), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                ForEach(history) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Rate", point.rate)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }

                if !isDragging {
                    if let min = minPoint {
                        PointMark(x: .value("Date", min.date), y: .value("Rate", min.rate))
                            .foregroundStyle(.red)
                            .symbolSize(70)
                            .annotation(position: .bottom, spacing: 8) {
                                extremeLabel(rate: min.rate, label: "최저", color: .red)
                            }
                    }
                    if let max = maxPoint {
                        PointMark(x: .value("Date", max.date), y: .value("Rate", max.rate))
                            .foregroundStyle(.green)
                            .symbolSize(70)
                            .annotation(position: .top, spacing: 8) {
                                extremeLabel(rate: max.rate, label: "최고", color: .green)
                            }
                    }
                }

                if let selected = selectedPoint {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

                    PointMark(x: .value("Date", selected.date), y: .value("Rate", selected.rate))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(80)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel(format: xAxisFormat)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .number.precision(.fractionLength(0)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let plotOrigin = geo[proxy.plotAreaFrame].origin
                                    let x = value.location.x - plotOrigin.x
                                    guard x >= 0, x <= geo[proxy.plotAreaFrame].width else { return }
                                    if let date: Date = proxy.value(atX: x) {
                                        withAnimation(.easeInOut(duration: 0.1)) {
                                            selectedPoint = nearestPoint(to: date)
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedPoint = nil
                                    }
                                }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private func nearestPoint(to date: Date) -> RateDataPoint? {
        history.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private func extremeLabel(rate: Double, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(rate, format: .number.precision(.fractionLength(0)))
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .glassEffect(in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Data Loading

    private func loadAll(force: Bool = false) async {
        if force { ExchangeRateService.shared.clearCache() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRate() }
            group.addTask { await self.loadHistory() }
        }
    }

    private func loadRate() async {
        isLoadingRate = true
        defer { isLoadingRate = false }
        do {
            let rate = try await ExchangeRateService.shared.fetchLatestRate()
            ExchangeRateService.shared.saveRate(rate)
            withAnimation { exchangeRate = rate }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            exchangeRate = ExchangeRateService.shared.loadRate()
        }
    }

    private func loadHistory() async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        do {
            let points = try await ExchangeRateService.shared.fetchHistory(for: selectedPeriod)
            withAnimation { history = points }
        } catch {
            history = []
        }
    }
}

#Preview {
    ContentView()
}
