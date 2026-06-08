import SwiftUI
import Charts

// MARK: - Model

struct PatternMatch: Identifiable {
    let id = UUID()
    let startDate: Date
    let matchPoints: [RateDataPoint]
    let forecastPoints: [RateDataPoint]
    let similarity: Double
    let forecastChange: Double
}

// MARK: - Algorithm

enum PatternMatcher {
    static let windowSize  = 14
    static let forecastSize = 14

    static func findMatches(in history: [RateDataPoint]) -> [PatternMatch] {
        guard history.count >= windowSize * 2 + forecastSize else { return [] }

        let current     = Array(history.suffix(windowSize)).map(\.rate)
        let currentNorm = toReturns(current)

        var candidates: [(dist: Double, idx: Int)] = []
        let limit = history.count - windowSize - forecastSize

        for i in 0..<limit {
            let norm = toReturns(Array(history[i..<(i + windowSize)]).map(\.rate))
            candidates.append((euclidean(currentNorm, norm), i))
        }
        candidates.sort { $0.dist < $1.dist }

        // Deduplicate overlapping windows
        var picks: [(Double, Int)] = []
        for c in candidates {
            if picks.allSatisfy({ abs($0.1 - c.idx) >= windowSize }) {
                picks.append((c.dist, c.idx))
                if picks.count == 3 { break }
            }
        }

        return picks.map { dist, idx in
            let mp  = Array(history[idx..<(idx + windowSize)])
            let fp  = Array(history[(idx + windowSize)..<(idx + windowSize + forecastSize)])
            let base = mp.first?.rate ?? 1
            let end  = fp.last?.rate  ?? base
            return PatternMatch(
                startDate:     mp.first?.date ?? Date(),
                matchPoints:   mp,
                forecastPoints: fp,
                similarity:    min(99, max(55, 100 - dist * 10)),
                forecastChange: (end - base) / base * 100
            )
        }
    }

    private static func toReturns(_ rates: [Double]) -> [Double] {
        guard let first = rates.first, first > 0 else { return rates }
        return rates.map { ($0 - first) / first * 100 }
    }

    private static func euclidean(_ a: [Double], _ b: [Double]) -> Double {
        sqrt(zip(a, b).map { pow($0 - $1, 2) }.reduce(0, +))
    }
}

// MARK: - Mini Sparkline

struct PatternSparkline: View {
    let matchPoints:    [RateDataPoint]
    let forecastPoints: [RateDataPoint]

    private var forecastColor: Color {
        guard let f = forecastPoints.first?.rate,
              let l = forecastPoints.last?.rate else { return .accentColor }
        return l >= f ? .red : .green
    }

    var body: some View {
        Chart {
            ForEach(Array(matchPoints.enumerated()), id: \.offset) { i, pt in
                LineMark(x: .value("i", i), y: .value("v", pt.rate),
                         series: .value("s", "m"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }

            if !forecastPoints.isEmpty {
                let bridge  = [matchPoints.last].compactMap { $0 }
                let bridged = bridge + forecastPoints
                let offset  = matchPoints.count - 1
                ForEach(Array(bridged.enumerated()), id: \.offset) { i, pt in
                    LineMark(x: .value("i", offset + i), y: .value("v", pt.rate),
                             series: .value("s", "f"))
                        .foregroundStyle(forecastColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .interpolationMethod(.monotone)
                }
                RuleMark(x: .value("div", matchPoints.count - 1))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Main View

struct PatternMatchView: View {
    let history:   [RateDataPoint]
    let isLoading: Bool

    @State private var matches:     [PatternMatch] = []
    @State private var isComputing = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("5년 데이터 로딩 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isComputing {
                ProgressView("패턴 분석 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("데이터 로딩 후 패턴 탭을 다시 선택하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollContent
            }
        }
        .task(id: history.count) {
            guard history.count >= PatternMatcher.windowSize * 2 + PatternMatcher.forecastSize else { return }
            isComputing = true
            let result = await Task.detached(priority: .userInitiated) {
                PatternMatcher.findMatches(in: history)
            }.value
            matches     = result
            isComputing = false
        }
    }

    // MARK: Scroll Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                currentSection
                Divider()
                matchesSection
            }
            .padding(.bottom, 8)
        }
    }

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("현재 패턴 (최근 14일)", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            PatternSparkline(matchPoints: Array(history.suffix(14)), forecastPoints: [])
                .frame(height: 56)
        }
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("가장 유사한 과거 패턴", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(matches.enumerated()), id: \.element.id) { idx, m in
                matchCard(m, rank: idx + 1)
            }

            summaryCard
        }
    }

    private func matchCard(_ match: PatternMatch, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(rank)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(match.startDate, format: .dateTime.year().month().day())
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "유사도 %.0f%%", match.similarity))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.7), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 12) {
                PatternSparkline(matchPoints: match.matchPoints, forecastPoints: match.forecastPoints)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("이후 14일").font(.system(size: 9)).foregroundStyle(.secondary)
                    let up = match.forecastChange >= 0
                    HStack(spacing: 2) {
                        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                        Text(String(format: "%+.1f%%", match.forecastChange))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(up ? Color.red : Color.green)
                }
                .frame(width: 60)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryCard: some View {
        let avg = matches.map(\.forecastChange).reduce(0, +) / Double(max(matches.count, 1))
        let up  = avg >= 0
        return HStack(spacing: 8) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.caption2)
                .foregroundStyle(up ? Color.red : Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("시나리오 평균").font(.caption2).foregroundStyle(.secondary)
                Text("이후 14일 \(String(format: "%+.1f%%", avg)) \(up ? "상승" : "하락") 경향")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(up ? Color.red : Color.green)
            }
            Spacer()
        }
        .padding(12)
        .background((up ? Color.red : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
