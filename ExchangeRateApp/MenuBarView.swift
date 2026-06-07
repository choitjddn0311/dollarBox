import SwiftUI
import Charts

struct MenuBarView: View {
    @AppStorage("menuBarPair") private var pairRaw: String = CurrencyPair.usdkrw.rawValue
    @State private var rate: ExchangeRate?
    @State private var history: [RateDataPoint] = []
    @State private var isLoading = false
    @Environment(\.openWindow) private var openWindow
    @Environment(RateMonitor.self) private var rateMonitor

    private var pair: CurrencyPair {
        CurrencyPair(rawValue: pairRaw) ?? .usdkrw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $pairRaw) {
                ForEach(CurrencyPair.allCases) { p in
                    Text(p.label).tag(p.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if isLoading && rate == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let rate {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("₩")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text((rate.rate * pair.displayMultiplier)
                            .formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }

                if let change = rate.change, let pct = rate.changePercent {
                    HStack(spacing: 3) {
                        Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                        Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) (\(pct >= 0 ? "+" : "")\(pct.formatted(.number.precision(.fractionLength(2))))%)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(change >= 0 ? Color.green : Color.red)
                }

                Text("\(pair.displayUnitLabel) 기준  ·  \(rate.updatedAt.formatted(date: .omitted, time: .shortened)) 업데이트")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !history.isEmpty {
                sparkline.frame(height: 52)
            }

            Divider()

            HStack {
                Button {
                    Task { await loadData() }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Spacer()

                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("앱 열기", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 240)
        .task { await loadData() }
        .onChange(of: pairRaw) { _, _ in
            rate = nil
            history = []
            Task { await loadData() }
        }
    }

    private var sparkline: some View {
        let rates = history.map(\.rate)
        let lo = rates.min() ?? 0
        let hi = rates.max() ?? 1
        let pad = (hi - lo) * 0.25
        let domain = (lo - pad)...(hi + pad)

        return Chart(history) { pt in
            AreaMark(
                x: .value("Date", pt.date),
                yStart: .value("Base", domain.lowerBound),
                yEnd: .value("Rate", pt.rate)
            )
            .foregroundStyle(LinearGradient(
                colors: [Color.accentColor.opacity(0.25), .clear],
                startPoint: .top, endPoint: .bottom
            ))
            .interpolationMethod(.monotone)

            LineMark(x: .value("Date", pt.date), y: .value("Rate", pt.rate))
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        let p = pair
        async let rateTask    = ExchangeRateService.shared.fetchLatestRate(pair: p)
        async let historyTask = ExchangeRateService.shared.fetchHistory(for: .week, pair: p)

        if let r = try? await rateTask {
            withAnimation { rate = r }
            rateMonitor.update(rate: r.rate, pair: p)
        }
        history = (try? await historyTask) ?? []
    }
}
