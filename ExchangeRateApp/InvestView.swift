import SwiftUI

// MARK: - Models

private struct TimingResult {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let isGood: Bool
    }

    let score: Int
    let items: [Item]

    var summary: String {
        switch score {
        case 75...100: return "역사적으로 낮은 구간 — 적극 매수 고려"
        case 50..<75:  return "비교적 유리한 구간 — 분할 매수 고려"
        case 25..<50:  return "보통 구간 — 관망 또는 소량 매수"
        default:       return "고점 구간 — 매수 주의"
        }
    }

    var color: Color {
        switch score {
        case 75...100: return .green
        case 50..<75:  return Color(hue: 0.35, saturation: 0.7, brightness: 0.7)
        case 25..<50:  return .orange
        default:       return .red
        }
    }
}

enum DCAFrequency: String, CaseIterable, Identifiable {
    case weekly  = "매주"
    case monthly = "매월"
    var id: String { rawValue }
    var step: Int { self == .weekly ? 5 : 21 }  // trading days
}

private struct DCAEntry: Identifiable {
    let id   = UUID()
    let seq  : Int
    let date : Date
    let rate : Double
    let usd  : Double
}

// MARK: - Main View

struct InvestView: View {
    let exchangeRate: ExchangeRate?
    let yearHistory : [RateDataPoint]
    let pair        : CurrencyPair

    @State private var investAmount = ""
    @State private var targetRate   = ""
    @State private var dcaAmount    = ""
    @State private var dcaPeriods   = 8
    @State private var dcaFreq      : DCAFrequency = .weekly

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                timingCard
                profitCard
                dcaCard
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Indicators (1Y 데이터 기준, 자체 계산)

    private func slidingMA(_ period: Int) -> [RateDataPoint] {
        guard yearHistory.count >= period else { return [] }
        var sum = yearHistory[0..<period].reduce(0.0) { $0 + $1.rate }
        var result = [RateDataPoint(date: yearHistory[period - 1].date, rate: sum / Double(period))]
        result.reserveCapacity(yearHistory.count - period + 1)
        for i in period..<yearHistory.count {
            sum += yearHistory[i].rate - yearHistory[i - period].rate
            result.append(RateDataPoint(date: yearHistory[i].date, rate: sum / Double(period)))
        }
        return result
    }

    private var rsiLast: Double? {
        let p = 14
        guard yearHistory.count > p else { return nil }
        var avgG = 0.0, avgL = 0.0
        for i in 1...p {
            let d = yearHistory[i].rate - yearHistory[i - 1].rate
            avgG += max(0, d); avgL += max(0, -d)
        }
        avgG /= Double(p); avgL /= Double(p)
        var last = 50.0
        for i in p..<yearHistory.count - 1 {
            let d = yearHistory[i + 1].rate - yearHistory[i].rate
            avgG = (avgG * Double(p - 1) + max(0,  d)) / Double(p)
            avgL = (avgL * Double(p - 1) + max(0, -d)) / Double(p)
            last = avgL == 0 ? 100 : 100 - (100 / (1 + avgG / avgL))
        }
        return last
    }

    private var timing: TimingResult {
        var score = 0.0
        var items: [TimingResult.Item] = []
        let current = exchangeRate?.rate ?? 0

        let rates = yearHistory.map(\.rate)
        if let lo = rates.min(), let hi = rates.max(), hi > lo, current > 0 {
            let pos = (current - lo) / (hi - lo)
            score += (1 - pos) * 40
            items.append(.init(label: "52주 위치",
                               value: String(format: "하위 %.0f%%", pos * 100),
                               isGood: pos < 0.5))
        }

        if let rsi = rsiLast {
            let sub: Double = rsi < 30 ? 35 : rsi < 50 ? 17.5 + (50 - rsi) / 20 * 17.5
                                        : rsi < 70 ? (70 - rsi) / 20 * 17.5 : 0
            score += sub
            let tag = rsi < 30 ? "과매도" : rsi < 70 ? "중립" : "과매수"
            items.append(.init(label: "RSI (14)",
                               value: String(format: "%.1f · %@", rsi, tag),
                               isGood: rsi < 50))
        }

        let ma7 = slidingMA(7)
        if let m7 = ma7.last?.rate, current > 0 {
            let dev = (current - m7) / m7 * 100
            score += dev < 0 ? 15 : 0
            items.append(.init(label: "MA7 대비",
                               value: String(format: "%+.1f%%", dev),
                               isGood: dev < 0))
        }

        let ma30 = slidingMA(30)
        if let m30 = ma30.last?.rate, current > 0 {
            let dev = (current - m30) / m30 * 100
            score += dev < 0 ? 10 : 0
            items.append(.init(label: "MA30 대비",
                               value: String(format: "%+.1f%%", dev),
                               isGood: dev < 0))
        }

        return TimingResult(score: Int(score.rounded()), items: items)
    }

    // MARK: - Timing Card

    private var timingCard: some View {
        let t = timing
        return VStack(alignment: .leading, spacing: 14) {
            Label("지금 살까?", systemImage: "gauge.open.with.lines.needle.33percent")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 11)
                    Circle()
                        .trim(from: 0, to: CGFloat(t.score) / 100)
                        .stroke(t.color,
                                style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.7), value: t.score)
                    VStack(spacing: 2) {
                        Text("\(t.score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(t.color)
                        Text("/ 100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 106, height: 106)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(t.items) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.isGood
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.circle.fill")
                                .foregroundStyle(item.isGood ? .green : .orange)
                                .font(.caption)
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.value)
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }

            Text(t.summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(t.color)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Profit Card

    private var profitCard: some View {
        let current = (exchangeRate?.rate ?? 0) * pair.displayMultiplier
        let usd     = Double(investAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        let target  = Double(targetRate.replacingOccurrences(of: ",", with: "")) ?? 0
        let nowKRW  = usd * current
        let tgtKRW  = usd * target
        let profit  = tgtKRW - nowKRW
        let pct     = nowKRW > 0 ? profit / nowKRW * 100 : 0
        let valid   = usd > 0 && target > 0 && current > 0

        return VStack(alignment: .leading, spacing: 14) {
            Label("얼마나 벌까?", systemImage: "dollarsign.circle")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                inputField(title: "투자 금액", symbol: pair.symbol,
                           placeholder: "0", text: $investAmount)
                inputField(title: "목표 환율", symbol: "₩",
                           placeholder: "0", text: $targetRate)
            }

            if valid {
                VStack(spacing: 8) {
                    row("현재 환율 기준 원화", "₩\(Int(nowKRW).formatted())")
                    row("목표 도달 시 원화",   "₩\(Int(tgtKRW).formatted())")
                    Divider()
                    HStack {
                        Text("예상 수익")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(profit >= 0 ? "+" : "")₩\(Int(profit).formatted())")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(profit >= 0 ? .green : .red)
                            Text(String(format: "%+.2f%%", pct))
                                .font(.caption)
                                .foregroundStyle(profit >= 0 ? .green : .red)
                        }
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text("금액과 목표 환율을 입력하세요")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - DCA Card

    private var dcaEntries: [DCAEntry] {
        let usd = Double(dcaAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        guard usd > 0, !yearHistory.isEmpty else { return [] }
        var result: [DCAEntry] = []
        var idx = yearHistory.count - 1
        for i in (0..<dcaPeriods).reversed() {
            guard idx >= 0 else { break }
            result.insert(DCAEntry(seq: i + 1,
                                   date: yearHistory[idx].date,
                                   rate: yearHistory[idx].rate,
                                   usd: usd), at: 0)
            idx = max(0, idx - dcaFreq.step)
        }
        return result
    }

    private var dcaCard: some View {
        let current  = exchangeRate?.rate ?? 0
        let entries  = dcaEntries
        let totalUSD = entries.reduce(0) { $0 + $1.usd }
        let totalKRW = entries.reduce(0) { $0 + $1.rate * $1.usd }
        let avgRate  = totalUSD > 0 ? totalKRW / totalUSD : 0
        let nowKRW   = totalUSD * current
        let profit   = nowKRW - totalKRW
        let pct      = totalKRW > 0 ? profit / totalKRW * 100 : 0
        let hasData  = !entries.isEmpty

        return VStack(alignment: .leading, spacing: 14) {
            Label("분할 매수 시뮬레이션", systemImage: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))

            // Controls
            HStack(spacing: 10) {
                inputField(title: "회차당 금액", symbol: pair.symbol,
                           placeholder: "0", text: $dcaAmount)
                    .frame(maxWidth: 130)

                VStack(alignment: .leading, spacing: 4) {
                    Text("주기").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("", selection: $dcaFreq) {
                        ForEach(DCAFrequency.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("횟수 (\(dcaPeriods)회)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(dcaPeriods) },
                        set: { dcaPeriods = Int($0) }
                    ), in: 2...52, step: 1)
                }
            }

            if !hasData {
                Text("금액을 입력하면 과거 실제 환율로 시뮬레이션합니다")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    // Table header
                    HStack(spacing: 0) {
                        Text("회차").tableHeader().frame(width: 34)
                        Text("날짜").tableHeader().frame(maxWidth: .infinity, alignment: .leading)
                        Text("환율").tableHeader().frame(width: 80, alignment: .trailing)
                        Text("원화").tableHeader().frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                    ForEach(entries) { e in
                        HStack(spacing: 0) {
                            Text("\(e.seq)").font(.caption2).foregroundStyle(.secondary).frame(width: 34)
                            Text(e.date, format: .dateTime.year().month().day())
                                .font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
                            Text("₩\(Int(e.rate).formatted())")
                                .font(.caption2).frame(width: 80, alignment: .trailing)
                            Text("₩\(Int(e.rate * e.usd).formatted())")
                                .font(.caption2.weight(.medium)).frame(width: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        if e.seq < entries.count {
                            Divider().padding(.horizontal, 6)
                        }
                    }
                }

                // Summary
                VStack(spacing: 8) {
                    row("총 투자",
                        "\(pair.symbol)\(String(format: "%.0f", totalUSD))  ·  ₩\(Int(totalKRW).formatted())")
                    row("평균 매입 환율", "₩\(Int(avgRate).formatted())")
                    Divider()
                    HStack {
                        Text("현재 평가 손익")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(profit >= 0 ? "+" : "")₩\(Int(profit).formatted())")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(profit >= 0 ? .green : .red)
                            Text(String(format: "%+.2f%%", pct))
                                .font(.caption)
                                .foregroundStyle(profit >= 0 ? .green : .red)
                        }
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func inputField(title: String, symbol: String,
                            placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(symbol).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                TextField(placeholder, text: text).font(.callout.weight(.semibold)).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium))
        }
    }
}

// MARK: - Text Extension

private extension Text {
    func tableHeader() -> Text {
        self.font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
