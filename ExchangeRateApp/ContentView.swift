import SwiftUI
import Charts
import WidgetKit

private enum AppTab { case chart, converter, journal }
private enum ConverterFocus: Hashable { case usd, krw }

struct ContentView: View {
    @AppStorage("themeMode") private var themeMode: String = "system"
    @Environment(RateMonitor.self) private var rateMonitor

    @State private var selectedPair: CurrencyPair = .usdkrw
    @State private var exchangeRate: ExchangeRate?
    @State private var history: [RateDataPoint] = []
    @State private var yearHistory: [RateDataPoint] = []   // 52W 게이지용
    @State private var selectedPeriod: RatePeriod = .week
    @State private var isLoadingRate = false
    @State private var isLoadingChart = false
    @State private var selectedPoint: RateDataPoint? = nil

    // 환산 탭
    @State private var activeTab: AppTab = .chart
    @State private var baseText: String = ""
    @State private var krwText: String = ""
    @FocusState private var converterFocus: ConverterFocus?

    // 차트 지표 설정
    @AppStorage("showMA7")            private var showMA7            = true
    @AppStorage("showMA30")           private var showMA30           = true
    @AppStorage("showBollingerBands") private var showBollingerBands = false
    @AppStorage("showRSI")            private var showRSI            = false
    @AppStorage("showPrediction")     private var showPrediction     = false
    @AppStorage("showWeekGauge")      private var showWeekGauge      = true
    @State private var showSettings = false

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

    private var currentRates: [CurrencyPair: Double] {
        var rates: [CurrencyPair: Double] = [:]
        for pair in CurrencyPair.allCases {
            if let r = ExchangeRateService.shared.loadRate(pair: pair)?.rate {
                rates[pair] = r
            }
        }
        if let live = exchangeRate?.rate { rates[selectedPair] = live }
        return rates
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
        case .week:     return .dateTime.weekday(.abbreviated)
        case .month:    return .dateTime.day().month(.abbreviated)
        case .year:     return .dateTime.month(.abbreviated)
        case .fiveYear: return .dateTime.year()
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

    // MARK: - 예측선 (선형 회귀)

    private var predictionPoints: [RateDataPoint] {
        guard showPrediction, selectedPeriod != .week, history.count >= 10 else { return [] }
        let recent = Array(history.suffix(min(30, history.count)))
        let n = Double(recent.count)
        let xs = (0..<recent.count).map { Double($0) }
        let ys = recent.map(\.rate)

        let sumX  = xs.reduce(0, +)
        let sumY  = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return [] }

        let slope     = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n

        let interval   = recent.last!.date.timeIntervalSince(recent.first!.date) / Double(recent.count - 1)
        let lastDate   = recent.last!.date
        let futureDays = selectedPeriod == .year || selectedPeriod == .fiveYear ? 30 : 7

        return (0...futureDays).map { i in
            let x = Double(recent.count - 1) + Double(i)
            return RateDataPoint(
                date: lastDate.addingTimeInterval(interval * Double(i)),
                rate: max(0, slope * x + intercept)
            )
        }
    }

    // MARK: - Bollinger Bands (20일)

    private struct BBPoint: Identifiable {
        let id = UUID()
        let date: Date
        let upper: Double
        let middle: Double
        let lower: Double
    }

    private var bbPoints: [BBPoint] {
        let p = 20
        guard history.count >= p else { return [] }
        return (p - 1 ..< history.count).map { i in
            let slice = history[(i - p + 1)...i].map(\.rate)
            let avg   = slice.reduce(0, +) / Double(p)
            let std   = sqrt(slice.map { pow($0 - avg, 2) }.reduce(0, +) / Double(p))
            return BBPoint(date: history[i].date, upper: avg + 2 * std, middle: avg, lower: avg - 2 * std)
        }
    }

    // MARK: - RSI (14일)

    private var rsiPoints: [RateDataPoint] {
        let p = 14
        guard history.count > p else { return [] }
        var gains  = [Double]()
        var losses = [Double]()
        for i in 1 ..< history.count {
            let d = history[i].rate - history[i - 1].rate
            gains.append(max(0,  d))
            losses.append(max(0, -d))
        }
        var avgG = gains[0 ..< p].reduce(0, +)  / Double(p)
        var avgL = losses[0 ..< p].reduce(0, +) / Double(p)
        var result = [RateDataPoint]()
        for i in p ..< gains.count {
            avgG = (avgG * Double(p - 1) + gains[i])  / Double(p)
            avgL = (avgL * Double(p - 1) + losses[i]) / Double(p)
            let rsi = avgL == 0 ? 100.0 : 100 - (100 / (1 + avgG / avgL))
            result.append(RateDataPoint(date: history[i + 1].date, rate: rsi))
        }
        return result
    }

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
        .frame(minWidth: 700, minHeight: 560)
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
                HStack(spacing: 8) {
                    Text(selectedPair.headerText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedPair) {
                        ForEach(CurrencyPair.allCases) { pair in
                            Text(pair.label).tag(pair)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: selectedPair) { _, _ in
                        exchangeRate = nil
                        history = []
                        yearHistory = []
                        selectedPoint = nil
                        baseText = ""
                        krwText = ""
                        Task { await loadAll() }
                    }
                }

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
                                let v = $0 * selectedPair.displayMultiplier
                                return v.formatted(.number.precision(.fractionLength(2)))
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
                    Text("일지").tag(AppTab.journal)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                if activeTab == .chart {
                    periodPicker
                }

                if activeTab != .journal {
                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(in: Circle())
                    .popover(isPresented: $showSettings, arrowEdge: .top) {
                        SettingsView()
                    }
                }
            }

            if activeTab == .chart && showWeekGauge && !yearHistory.isEmpty,
               let current = exchangeRate?.rate {
                weekGauge(current: current)
            }

            if activeTab == .chart && selectedPeriod != .week && !history.isEmpty {
                chartLegend
            }

            if activeTab == .chart {
                chartArea
                if showRSI && selectedPeriod != .week && !rsiPoints.isEmpty {
                    Divider().padding(.vertical, 2)
                    rsiChart
                        .frame(height: 90)
                }
            } else if activeTab == .converter {
                converterArea
            } else {
                JournalView(currentRates: currentRates)
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

    // MARK: - Chart Legend

    private var chartLegend: some View {
        HStack(spacing: 14) {
            legendItem(color: .accentColor, dash: [],      label: "환율")
            if showMA7  { legendItem(color: .orange, dash: [4, 3], label: "MA 7") }
            if showMA30 && selectedPeriod == .year || selectedPeriod == .fiveYear { legendItem(color: .purple, dash: [4, 3], label: "MA 30") }
            if showBollingerBands && !bbPoints.isEmpty {
                legendItem(color: Color(red: 0.9, green: 0.7, blue: 0.1), dash: [3, 2], label: "볼린저")
            }
            if showPrediction && !predictionPoints.isEmpty {
                legendItem(color: .mint, dash: [5, 3], label: "예측")
            }
        }
    }

    private func legendItem(color: Color, dash: [CGFloat], label: String) -> some View {
        HStack(spacing: 5) {
            Path { p in
                p.move(to: .init(x: 0, y: 4))
                p.addLine(to: .init(x: 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash))
            .frame(width: 18, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Converter

    private var converterArea: some View {
        VStack(spacing: 0) {
            Spacer()

            // 외화 입력
            converterRow(
                symbol: selectedPair.symbol,
                currency: selectedPair.label,
                placeholder: "\(selectedPair.label) 입력",
                text: $baseText
            )
            .focused($converterFocus, equals: .usd)
            .onChange(of: baseText) { _, val in
                guard converterFocus == .usd else { return }
                let cleaned = val.replacingOccurrences(of: ",", with: "")
                if let amount = Double(cleaned), let rate = exchangeRate?.rate {
                    krwText = (amount * rate).formatted(.number.precision(.fractionLength(0)))
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
                if let krw = Double(cleaned), let rate = exchangeRate?.rate, rate > 0 {
                    baseText = (krw / rate).formatted(.number.precision(.fractionLength(2)))
                } else if cleaned.isEmpty {
                    baseText = ""
                }
            }

            Spacer()

            // 현재 환율 안내
            if let rate = exchangeRate?.rate {
                let displayRate = (rate * selectedPair.displayMultiplier)
                    .formatted(.number.precision(.fractionLength(2)))
                Text("현재 환율  \(selectedPair.displayUnitLabel) = ₩\(displayRate)")
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
                // ── 볼린저 밴드 (가장 뒤)
                if showBollingerBands && selectedPeriod != .week {
                    let bbColor = Color(red: 0.9, green: 0.7, blue: 0.1)
                    ForEach(bbPoints) { pt in
                        LineMark(x: .value("Date", pt.date), y: .value("Rate", pt.upper),
                                 series: .value("S", "bb-upper"))
                            .foregroundStyle(bbColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(bbPoints) { pt in
                        LineMark(x: .value("Date", pt.date), y: .value("Rate", pt.lower),
                                 series: .value("S", "bb-lower"))
                            .foregroundStyle(bbColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(bbPoints) { pt in
                        LineMark(x: .value("Date", pt.date), y: .value("Rate", pt.middle),
                                 series: .value("S", "bb-mid"))
                            .foregroundStyle(bbColor.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .interpolationMethod(.monotone)
                    }
                }

                // ── 가격 영역 및 라인
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
                        y: .value("Rate", point.rate),
                        series: .value("S", "rate")
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }

                // ── MA 라인
                if showMA7 && selectedPeriod != .week {
                    ForEach(ma7) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Rate", point.rate),
                            series: .value("S", "ma7")
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                    }
                }

                if showMA30 && selectedPeriod == .year || selectedPeriod == .fiveYear {
                    ForEach(ma30) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Rate", point.rate),
                            series: .value("S", "ma30")
                        )
                        .foregroundStyle(Color.purple)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                    }
                }

                // ── 예측선 (선형 회귀)
                if showPrediction && !predictionPoints.isEmpty {
                    ForEach(predictionPoints) { pt in
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Rate", pt.rate),
                            series: .value("S", "pred")
                        )
                        .foregroundStyle(Color.mint.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
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

    // MARK: - RSI Chart

    private var rsiChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RSI (14)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Chart {
                // 과매수 / 과매도 기준선
                RuleMark(y: .value("과매수", 70))
                    .foregroundStyle(Color.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("70").font(.system(size: 9)).foregroundStyle(.red.opacity(0.7))
                    }
                RuleMark(y: .value("과매도", 30))
                    .foregroundStyle(Color.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("30").font(.system(size: 9)).foregroundStyle(.blue.opacity(0.7))
                    }

                // RSI 라인
                ForEach(rsiPoints) { pt in
                    LineMark(x: .value("Date", pt.date), y: .value("RSI", pt.rate),
                             series: .value("S", "rsi"))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }

                // 드래그 선택 지점
                if let selected = selectedPoint,
                   let rsiPt = rsiPoints.min(by: {
                       abs($0.date.timeIntervalSince(selected.date)) < abs($1.date.timeIntervalSince(selected.date))
                   }) {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    PointMark(x: .value("Date", rsiPt.date), y: .value("RSI", rsiPt.rate))
                        .foregroundStyle(Color.primary)
                        .symbolSize(50)
                        .annotation(position: .top) {
                            Text(rsiPt.rate, format: .number.precision(.fractionLength(1)))
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: xAxisFormat).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 30, 50, 70, 100]) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 52W Gauge

    private func weekGauge(current: Double) -> some View {
        let rates = yearHistory.map(\.rate)
        let lo = rates.min() ?? current
        let hi = rates.max() ?? current
        let range = hi - lo
        let pos = range > 0 ? min(max((current - lo) / range, 0), 1) : 0.5
        let m = selectedPair.displayMultiplier

        return VStack(spacing: 5) {
            HStack {
                Text("52W 범위").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((pos * 100).rounded()))% 위치")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1)).frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.5), Color.green.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * pos, height: 4)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 11, height: 11)
                        .shadow(color: .accentColor.opacity(0.4), radius: 3)
                        .offset(x: geo.size.width * pos - 5.5, y: -3.5)
                }
            }
            .frame(height: 11)

            HStack {
                Text("₩\(Int(lo * m).formatted())")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("₩\(Int(hi * m).formatted())")
                    .font(.caption2).foregroundStyle(.secondary)
            }
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
            group.addTask { await self.loadYearHistory() }
        }
    }

    private func loadYearHistory() async {
        guard yearHistory.isEmpty else { return }
        let pair = selectedPair
        if let points = try? await ExchangeRateService.shared.fetchHistory(for: .year, pair: pair) {
            withAnimation { yearHistory = points }
        }
    }

    private func loadRate() async {
        isLoadingRate = true
        defer { isLoadingRate = false }
        let pair = selectedPair
        do {
            let rate = try await ExchangeRateService.shared.fetchLatestRate(pair: pair)
            ExchangeRateService.shared.saveRate(rate, pair: pair)
            withAnimation { exchangeRate = rate }
            WidgetCenter.shared.reloadAllTimelines()
            rateMonitor.update(rate: rate.rate, pair: pair)
        } catch {
            exchangeRate = ExchangeRateService.shared.loadRate(pair: pair)
        }
    }

    private func loadHistory() async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        let pair = selectedPair
        do {
            let points = try await ExchangeRateService.shared.fetchHistory(for: selectedPeriod, pair: pair)
            withAnimation { history = points }
        } catch {
            history = []
        }
    }
}

#Preview {
    ContentView()
}
