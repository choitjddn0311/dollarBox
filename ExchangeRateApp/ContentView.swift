import SwiftUI
import Charts
import WidgetKit

private enum AppTab { case chart, converter }
private enum ConverterFocus: Hashable { case usd, krw }

struct ContentView: View {
    @AppStorage("themeMode") private var themeMode: String = "system"

    @State private var exchangeRate: ExchangeRate?
    @State private var history: [RateDataPoint] = []
    @State private var selectedPeriod: RatePeriod = .week
    @State private var isLoadingRate = false
    @State private var isLoadingChart = false
    @State private var selectedPoint: RateDataPoint? = nil

    // 환산 탭
    @State private var activeTab: AppTab = .chart
    @State private var usdText: String = ""
    @State private var krwText: String = ""
    @FocusState private var converterFocus: ConverterFocus?

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

    // MARK: - Moving Average

    private func movingAverage(period: Int) -> [RateDataPoint] {
        guard history.count >= period else { return [] }
        return (period - 1 ..< history.count).map { i in
            let slice = history[(i - period + 1)...i]
            let avg = slice.map(\.rate).reduce(0, +) / Double(period)
            return RateDataPoint(date: history[i].date, rate: avg)
        }
    }

    private var ma7:  [RateDataPoint] { movingAverage(period: 7) }
    private var ma30: [RateDataPoint] { movingAverage(period: 30) }
    private var displayedDate: Date?   { selectedPoint?.date ?? exchangeRate?.updatedAt }
    private var isDragging: Bool       { selectedPoint != nil }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 14) {
                ratePanel
                bottomPanel
            }
            .padding(20)
        }
        .frame(minWidth: 700, minHeight: 540)
        .preferredColorScheme(preferredScheme)
        .task { await loadAll() }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        Color(.windowBackgroundColor)
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
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("₩")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(displayedRate.map {
                                $0.formatted(.number.precision(.fractionLength(2)))
                            } ?? "--")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        }
                        .foregroundStyle(.primary)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)
                    }
                }
                .frame(height: 66)

                if !isDragging, let change = exchangeRate?.change, let pct = exchangeRate?.changePercent {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption2)
                        Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) (\(pct >= 0 ? "+" : "")\(pct.formatted(.number.precision(.fractionLength(2))))%)")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(change >= 0 ? Color.green : Color.red)
                    .transition(.opacity)
                }

                if let date = displayedDate {
                    Text(isDragging
                         ? date.formatted(date: .abbreviated, time: .omitted)
                         : "Updated \(date.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Bottom Panel (Chart + Converter 탭)

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("", selection: $activeTab) {
                    Text("차트").tag(AppTab.chart)
                    Text("환산").tag(AppTab.converter)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                if activeTab == .chart {
                    periodPicker
                }
            }

            if activeTab == .chart && selectedPeriod != .week && !history.isEmpty {
                maLegend
            }

            if activeTab == .chart {
                chartArea
            } else {
                converterArea
            }
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
        .frame(maxWidth: 200)
        .onChange(of: selectedPeriod) { _, _ in
            selectedPoint = nil
            Task { await loadHistory() }
        }
    }

    // MARK: - MA Legend

    private var maLegend: some View {
        HStack(spacing: 14) {
            maLegendItem(color: .accentColor, style: [], label: "환율")
            maLegendItem(color: .orange, style: [4, 3], label: "MA 7")
            if selectedPeriod == .year {
                maLegendItem(color: .purple, style: [4, 3], label: "MA 30")
            }
        }
    }

    private func maLegendItem(color: Color, style: [CGFloat], label: String) -> some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: style))
            .frame(width: 18, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Converter

    private var converterArea: some View {
        VStack(spacing: 0) {
            Spacer()

            // USD 입력
            converterRow(
                symbol: "$",
                currency: "USD",
                placeholder: "달러 입력",
                text: $usdText
            )
            .focused($converterFocus, equals: .usd)
            .onChange(of: usdText) { _, val in
                guard converterFocus == .usd else { return }
                let cleaned = val.replacingOccurrences(of: ",", with: "")
                if let usd = Double(cleaned), let rate = exchangeRate?.rate {
                    krwText = (usd * rate).formatted(.number.precision(.fractionLength(0)))
                } else if cleaned.isEmpty {
                    krwText = ""
                }
            }

            // 구분선 + 스왑 아이콘
            HStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
            }
            .padding(.vertical, 24)

            // KRW 입력
            converterRow(
                symbol: "₩",
                currency: "KRW",
                placeholder: "원화 입력",
                text: $krwText
            )
            .focused($converterFocus, equals: .krw)
            .onChange(of: krwText) { _, val in
                guard converterFocus == .krw else { return }
                let cleaned = val.replacingOccurrences(of: ",", with: "")
                if let krw = Double(cleaned), let rate = exchangeRate?.rate {
                    usdText = (krw / rate).formatted(.number.precision(.fractionLength(2)))
                } else if cleaned.isEmpty {
                    usdText = ""
                }
            }

            Spacer()

            // 현재 환율 안내
            if let rate = exchangeRate?.rate {
                Text("현재 환율  1 USD = ₩\(rate.formatted(.number.precision(.fractionLength(2))))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func converterRow(symbol: String, currency: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currency)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(symbol)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: text)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            colors: [Color.accentColor.opacity(0.2), .clear],
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

                // 7일 이동평균 (1M, 1Y)
                if selectedPeriod != .week {
                    ForEach(ma7) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("MA7", point.rate)
                        )
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                    }
                }

                // 30일 이동평균 (1Y)
                if selectedPeriod == .year {
                    ForEach(ma30) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("MA30", point.rate)
                        )
                        .foregroundStyle(Color.purple.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                    }
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
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

                    PointMark(x: .value("Date", selected.date), y: .value("Rate", selected.rate))
                        .foregroundStyle(Color.primary)
                        .symbolSize(80)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel(format: xAxisFormat)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
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
