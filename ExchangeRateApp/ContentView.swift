import SwiftUI
import Charts
import WidgetKit

private enum AppTab: String {
    case chart, converter, invest, journal, pattern, heatmap, alerts

    var label: String {
        switch self {
        case .chart:     return "차트"
        case .converter: return "환산"
        case .invest:    return "투자"
        case .journal:   return "일지"
        case .pattern:   return "패턴"
        case .heatmap:   return "시간대"
        case .alerts:    return "알림"
        }
    }

    var icon: String {
        switch self {
        case .chart:     return "chart.xyaxis.line"
        case .converter: return "arrow.left.arrow.right"
        case .invest:    return "chart.line.uptrend.xyaxis"
        case .journal:   return "book"
        case .pattern:   return "waveform.path.ecg"
        case .heatmap:   return "clock"
        case .alerts:    return "bell"
        }
    }
}
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

    // 패턴 DNA / 히트맵
    @State private var patternHistory:  [RateDataPoint] = []
    @State private var hourlyHistory:   [RateDataPoint] = []
    @State private var isLoadingPattern = false
    @State private var isLoadingHeatmap = false

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
    @AppStorage("showMACD")           private var showMACD           = false
    @AppStorage("showPrediction")     private var showPrediction     = false
    @AppStorage("showWeekGauge")      private var showWeekGauge      = true
    @AppStorage("showCandlestick")    private var showCandlestick    = false
    @AppStorage("showFibonacci")      private var showFibonacci      = false
    @State private var showSettings = false
    @State private var ohlcHistory: [OHLCDataPoint] = []

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

    // MARK: - Indicator Cache (드래그 중 재계산 방지)
    @State private var cachedMA7:        [RateDataPoint] = []
    @State private var cachedMA30:       [RateDataPoint] = []
    @State private var cachedBB:         [BBPoint]       = []
    @State private var cachedRSI:        [RateDataPoint] = []
    @State private var cachedPrediction: [RateDataPoint] = []
    @State private var cachedMin:        RateDataPoint?  = nil
    @State private var cachedMax:        RateDataPoint?  = nil
    @State private var cachedCurrentRates: [CurrencyPair: Double] = [:]
    @State private var cachedMACD: [MACDPoint] = []

    private var currentRates: [CurrencyPair: Double] { cachedCurrentRates }
    private var minPoint:     RateDataPoint?          { cachedMin }
    private var maxPoint:     RateDataPoint?          { cachedMax }

    private var yDomain: ClosedRange<Double> {
        guard let lo = cachedMin?.rate, let hi = cachedMax?.rate, lo < hi else {
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
        case .all:      return .dateTime.year()
        }
    }

    private var displayedRate: Double? { selectedPoint?.rate ?? exchangeRate?.rate }

    private var ma7:             [RateDataPoint] { cachedMA7 }
    private var ma30:            [RateDataPoint] { cachedMA30 }
    private var bbPoints:        [BBPoint]       { cachedBB }
    private var rsiPoints:       [RateDataPoint] { cachedRSI }
    private var predictionPoints:[RateDataPoint] { showPrediction && selectedPeriod != .week ? cachedPrediction : [] }
    private var displayedDate:   Date?           { selectedPoint?.date ?? exchangeRate?.updatedAt }
    private var isDragging:      Bool            { selectedPoint != nil }

    // MARK: - Indicator models

    private struct BBPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let upper: Double
        let middle: Double
        let lower: Double
    }

    private struct MACDPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let macd: Double
        let signal: Double
        let histogram: Double
    }

    // MARK: - Background Indicator Computation

    private func recomputeIndicators() async {
        let data   = history
        let period = selectedPeriod

        guard !data.isEmpty else { return }

        struct Snapshot {
            var ma7:        [RateDataPoint]
            var ma30:       [RateDataPoint]
            var bb:         [BBPoint]
            var rsi:        [RateDataPoint]
            var macd:       [MACDPoint]
            var prediction: [RateDataPoint]
            var min:        RateDataPoint?
            var max:        RateDataPoint?
        }

        let snap = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            // — min / max (단일 패스)
            var minPt = data[0], maxPt = data[0]
            for pt in data {
                if pt.rate < minPt.rate { minPt = pt }
                if pt.rate > maxPt.rate { maxPt = pt }
            }

            // — 슬라이딩 윈도우 MA  O(n)
            func slidingMA(_ p: Int) -> [RateDataPoint] {
                guard data.count >= p else { return [] }
                var sum = data[0..<p].reduce(0.0) { $0 + $1.rate }
                var result = [RateDataPoint]()
                result.reserveCapacity(data.count - p + 1)
                result.append(RateDataPoint(date: data[p - 1].date, rate: sum / Double(p)))
                for i in p..<data.count {
                    sum += data[i].rate - data[i - p].rate
                    result.append(RateDataPoint(date: data[i].date, rate: sum / Double(p)))
                }
                return result
            }

            // — 슬라이딩 윈도우 볼린저 밴드  O(n)
            let bbP = 20
            var bbResult = [BBPoint]()
            if data.count >= bbP {
                bbResult.reserveCapacity(data.count - bbP + 1)
                var wSum  = data[0..<bbP].reduce(0.0) { $0 + $1.rate }
                var wSum2 = data[0..<bbP].reduce(0.0) { $0 + $1.rate * $1.rate }
                func bbPoint(at i: Int) -> BBPoint {
                    let avg = wSum  / Double(bbP)
                    let variance = wSum2 / Double(bbP) - avg * avg
                    let std = variance > 0 ? sqrt(variance) : 0
                    return BBPoint(date: data[i].date,
                                   upper: avg + 2 * std, middle: avg, lower: avg - 2 * std)
                }
                bbResult.append(bbPoint(at: bbP - 1))
                for i in bbP..<data.count {
                    let out = data[i - bbP].rate
                    let inn = data[i].rate
                    wSum  += inn - out
                    wSum2 += inn * inn - out * out
                    bbResult.append(bbPoint(at: i))
                }
            }

            // — RSI 14일 Wilder  O(n)
            let rsiP = 14
            var rsiResult = [RateDataPoint]()
            if data.count > rsiP {
                rsiResult.reserveCapacity(data.count - rsiP)
                var avgG = 0.0, avgL = 0.0
                for i in 1...rsiP {
                    let d = data[i].rate - data[i - 1].rate
                    avgG += max(0,  d)
                    avgL += max(0, -d)
                }
                avgG /= Double(rsiP); avgL /= Double(rsiP)
                for i in rsiP..<data.count - 1 {
                    let d = data[i + 1].rate - data[i].rate
                    avgG = (avgG * Double(rsiP - 1) + max(0,  d)) / Double(rsiP)
                    avgL = (avgL * Double(rsiP - 1) + max(0, -d)) / Double(rsiP)
                    let rsi = avgL == 0 ? 100.0 : 100 - (100 / (1 + avgG / avgL))
                    rsiResult.append(RateDataPoint(date: data[i + 1].date, rate: rsi))
                }
            }

            // — MACD (EMA12 - EMA26, Signal EMA9)
            var macdResult = [MACDPoint]()
            if data.count >= 35 {
                func ema(_ n: Int) -> [Double] {
                    let k = 2.0 / Double(n + 1)
                    var out = [Double]()
                    out.reserveCapacity(data.count)
                    var e = data[0..<n].reduce(0.0) { $0 + $1.rate } / Double(n)
                    for _ in 0..<(n - 1) { out.append(0) }
                    out.append(e)
                    for i in n..<data.count {
                        e = data[i].rate * k + e * (1 - k)
                        out.append(e)
                    }
                    return out
                }
                let ema12 = ema(12)
                let ema26 = ema(26)
                var macdLine = (0..<data.count).map { ema12[$0] - ema26[$0] }
                let start = 25
                let sigP  = 9
                if data.count > start + sigP {
                    let k9 = 2.0 / Double(sigP + 1)
                    var sig = macdLine[start..<(start + sigP)].reduce(0.0, +) / Double(sigP)
                    for i in (start + sigP)..<data.count {
                        sig = macdLine[i] * k9 + sig * (1 - k9)
                        macdResult.append(MACDPoint(date: data[i].date,
                                                    macd: macdLine[i], signal: sig,
                                                    histogram: macdLine[i] - sig))
                    }
                }
            }

            // — 예측선 선형회귀  O(n)
            var predResult = [RateDataPoint]()
            if data.count >= 10 {
                let recent = Array(data.suffix(min(30, data.count)))
                let n = Double(recent.count)
                var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0
                for (i, pt) in recent.enumerated() {
                    let x = Double(i)
                    sumX += x; sumY += pt.rate
                    sumXY += x * pt.rate; sumX2 += x * x
                }
                let denom = n * sumX2 - sumX * sumX
                if denom != 0 {
                    let slope     = (n * sumXY - sumX * sumY) / denom
                    let intercept = (sumY - slope * sumX) / n
                    let interval  = recent.last!.date.timeIntervalSince(recent.first!.date) / Double(recent.count - 1)
                    let lastDate  = recent.last!.date
                    let futureDays = (period == .year || period == .fiveYear || period == .all) ? 30 : 7
                    predResult.reserveCapacity(futureDays + 1)
                    for i in 0...futureDays {
                        let x = Double(recent.count - 1 + i)
                        predResult.append(RateDataPoint(
                            date: lastDate.addingTimeInterval(interval * Double(i)),
                            rate: max(0, slope * x + intercept)
                        ))
                    }
                }
            }

            return Snapshot(ma7: slidingMA(7), ma30: slidingMA(30),
                            bb: bbResult, rsi: rsiResult, macd: macdResult, prediction: predResult,
                            min: minPt, max: maxPt)
        }.value

        cachedMA7        = snap.ma7
        cachedMA30       = snap.ma30
        cachedBB         = snap.bb
        cachedRSI        = snap.rsi
        cachedMACD       = snap.macd
        cachedPrediction = snap.prediction
        cachedMin        = snap.min
        cachedMax        = snap.max
    }

    private func recomputeCurrentRates() {
        var rates: [CurrencyPair: Double] = [:]
        for pair in CurrencyPair.allCases {
            if let r = ExchangeRateService.shared.loadRate(pair: pair)?.rate {
                rates[pair] = r
            }
        }
        if let live = exchangeRate?.rate { rates[selectedPair] = live }
        cachedCurrentRates = rates
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
        .task(id: "\(activeTab.rawValue)\(selectedPair.rawValue)") {
            if activeTab == .pattern && patternHistory.isEmpty {
                await loadPatternHistory()
            } else if activeTab == .heatmap && hourlyHistory.isEmpty {
                await loadHourlyHistory()
            }
        }
        .onChange(of: history.count)    { _, _ in Task { await recomputeIndicators() } }
        .onChange(of: exchangeRate?.rate) { _, _ in recomputeCurrentRates() }
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
                        ohlcHistory = []
                        yearHistory = []
                        patternHistory = []
                        hourlyHistory = []
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
                Menu {
                    ForEach([AppTab.chart, .converter, .invest, .journal, .pattern, .heatmap, .alerts], id: \.self) { tab in
                        Button {
                            activeTab = tab
                        } label: {
                            Label(tab.label, systemImage: tab.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: activeTab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(activeTab.label)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                if activeTab == .chart {
                    periodPicker
                }

                if activeTab == .chart || activeTab == .converter {
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
                if showMACD && selectedPeriod != .week && !cachedMACD.isEmpty {
                    Divider().padding(.vertical, 2)
                    macdChart
                        .frame(height: 90)
                }
            } else if activeTab == .converter {
                converterArea
            } else if activeTab == .invest {
                InvestView(exchangeRate: exchangeRate,
                           yearHistory: yearHistory,
                           pair: selectedPair)
            } else if activeTab == .journal {
                JournalView(currentRates: currentRates)
            } else if activeTab == .pattern {
                PatternMatchView(history: patternHistory, isLoading: isLoadingPattern)
            } else if activeTab == .heatmap {
                HeatmapView(hourlyData: hourlyHistory, isLoading: isLoadingHeatmap, pair: selectedPair)
            } else {
                AlertsView(currentRates: currentRates)
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
        .frame(maxWidth: 240)
        .onChange(of: selectedPeriod) { _, _ in
            selectedPoint = nil
            Task { await loadHistory() }
        }
    }

    // MARK: - Chart Legend

    private var chartLegend: some View {
        HStack(spacing: 14) {
            if !showCandlestick { legendItem(color: .accentColor, dash: [], label: "환율") }
            if showCandlestick  { legendItem(color: .green, dash: [], label: "양봉"); legendItem(color: .red, dash: [], label: "음봉") }
            if showMA7          { legendItem(color: .orange, dash: [4, 3], label: "MA 7") }
            if showMA30 && (selectedPeriod == .year || selectedPeriod == .fiveYear || selectedPeriod == .all) {
                legendItem(color: .purple, dash: [4, 3], label: "MA 30")
            }
            if showBollingerBands && !bbPoints.isEmpty {
                legendItem(color: Color(red: 0.9, green: 0.7, blue: 0.1), dash: [3, 2], label: "볼린저")
            }
            if showFibonacci { legendItem(color: .yellow, dash: [4, 3], label: "피보나치") }
            if showMACD && !cachedMACD.isEmpty {
                legendItem(color: .blue,   dash: [],      label: "MACD")
                legendItem(color: .orange, dash: [4, 3], label: "Signal")
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

                // ── 가격 (캔들스틱 or 라인)
                if showCandlestick && !ohlcHistory.isEmpty {
                    ForEach(ohlcHistory) { pt in
                        // wick
                        RuleMark(
                            x: .value("Date", pt.date),
                            yStart: .value("Low",  pt.low),
                            yEnd:   .value("High", pt.high)
                        )
                        .foregroundStyle(pt.isBullish ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    ForEach(ohlcHistory) { pt in
                        // body
                        BarMark(
                            x: .value("Date", pt.date),
                            yStart: .value("Open",  pt.isBullish ? pt.open  : pt.close),
                            yEnd:   .value("Close", pt.isBullish ? pt.close : pt.open)
                        )
                        .foregroundStyle(pt.isBullish ? Color.green.opacity(0.85) : Color.red.opacity(0.85))
                    }
                } else {
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
                }

                // ── 피보나치 되돌림 레벨
                if showFibonacci && selectedPeriod != .week,
                   let lo = cachedMin?.rate, let hi = cachedMax?.rate, hi > lo {
                    let fibLevels: [(Double, String)] = [
                        (0.000, "0%"),
                        (0.236, "23.6%"),
                        (0.382, "38.2%"),
                        (0.500, "50%"),
                        (0.618, "61.8%"),
                        (0.786, "78.6%"),
                        (1.000, "100%")
                    ]
                    ForEach(fibLevels, id: \.1) { ratio, label in
                        let price = lo + ratio * (hi - lo)
                        RuleMark(y: .value("Fib", price))
                            .foregroundStyle(Color.yellow.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text(label)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow.opacity(0.7))
                            }
                    }
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

                if showMA30 && (selectedPeriod == .year || selectedPeriod == .fiveYear || selectedPeriod == .all) {
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

    // MARK: - MACD Chart

    private var macdChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MACD").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            let histMax = cachedMACD.map { abs($0.histogram) }.max() ?? 1
            Chart {
                // 기준선
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                // 히스토그램
                ForEach(cachedMACD) { pt in
                    BarMark(
                        x: .value("Date", pt.date),
                        yStart: .value("Base", 0),
                        yEnd: .value("Hist", pt.histogram)
                    )
                    .foregroundStyle(pt.histogram >= 0
                                     ? Color.green.opacity(0.55)
                                     : Color.red.opacity(0.55))
                }

                // MACD 라인
                ForEach(cachedMACD) { pt in
                    LineMark(x: .value("Date", pt.date), y: .value("MACD", pt.macd),
                             series: .value("S", "macd"))
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }

                // Signal 라인
                ForEach(cachedMACD) { pt in
                    LineMark(x: .value("Date", pt.date), y: .value("Signal", pt.signal),
                             series: .value("S", "signal"))
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                }

                if let selected = selectedPoint,
                   let mpt = cachedMACD.min(by: {
                       abs($0.date.timeIntervalSince(selected.date)) < abs($1.date.timeIntervalSince(selected.date))
                   }) {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    PointMark(x: .value("Date", mpt.date), y: .value("MACD", mpt.macd))
                        .foregroundStyle(Color.blue)
                        .symbolSize(40)
                        .annotation(position: .top) {
                            Text(mpt.macd, format: .number.precision(.fractionLength(1)))
                                .font(.caption2.bold())
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                }
            }
            .chartYScale(domain: -histMax * 2.5...histMax * 2.5)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel(format: xAxisFormat).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .number.precision(.fractionLength(1)))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
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
            rateMonitor.update(rate: rate.rate, pair: pair, changePercent: rate.changePercent)
            AlertManager.shared.check(rate: rate.rate, for: pair)
        } catch {
            exchangeRate = ExchangeRateService.shared.loadRate(pair: pair)
        }
    }

    private func loadHistory() async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        let pair   = selectedPair
        let period = selectedPeriod
        do {
            let points = try await ExchangeRateService.shared.fetchHistory(for: period, pair: pair)
            withAnimation { history = points.filter { $0.rate > 0 } }
            let ohlc = ExchangeRateService.shared.cachedOHLC(for: period, pair: pair)
            withAnimation { ohlcHistory = ohlc }
        } catch {
            history = []
            ohlcHistory = []
        }
    }

    private func loadPatternHistory() async {
        guard patternHistory.isEmpty else { return }
        isLoadingPattern = true
        defer { isLoadingPattern = false }
        let pair = selectedPair
        if let pts = try? await ExchangeRateService.shared.fetchHistory(for: .fiveYear, pair: pair) {
            patternHistory = pts.filter { $0.rate > 0 }
        }
    }

    private func loadHourlyHistory() async {
        guard hourlyHistory.isEmpty else { return }
        isLoadingHeatmap = true
        defer { isLoadingHeatmap = false }
        let pair = selectedPair
        if let pts = try? await ExchangeRateService.shared.fetchHourlyHistory(pair: pair) {
            hourlyHistory = pts.filter { $0.rate > 0 }
        }
    }
}

#Preview {
    ContentView()
}
