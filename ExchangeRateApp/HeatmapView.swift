import SwiftUI

// MARK: - Precomputed Data

private struct HeatmapData {
    struct Cell {
        let weekday: Int   // 2=Mon … 6=Fri (Calendar, 1=Sun)
        let hour: Int
        let avg: Double
        let deviation: Double  // fraction from mean (e.g. -0.002 = -0.2%)
        let count: Int
    }

    let cells: [Cell]
    let mean: Double

    init(_ points: [RateDataPoint]) {
        var kstCal = Calendar(identifier: .gregorian)
        kstCal.timeZone = TimeZone(identifier: "Asia/Seoul")!

        var groups: [String: [Double]] = [:]
        for pt in points {
            let wd = kstCal.component(.weekday, from: pt.date)
            let h  = kstCal.component(.hour,    from: pt.date)
            guard (2...6).contains(wd), (8...18).contains(h) else { continue }
            groups["\(wd)_\(h)", default: []].append(pt.rate)
        }

        let allRelevant = groups.values.flatMap { $0 }
        let m = allRelevant.isEmpty ? 1.0 : allRelevant.reduce(0, +) / Double(allRelevant.count)
        mean = m

        cells = groups.compactMap { key, rates in
            let parts = key.split(separator: "_").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            let avg = rates.reduce(0, +) / Double(rates.count)
            return Cell(weekday: parts[0], hour: parts[1],
                        avg: avg, deviation: (avg - m) / m,
                        count: rates.count)
        }
    }

    func cell(weekday: Int, hour: Int) -> Cell? {
        cells.first { $0.weekday == weekday && $0.hour == hour }
    }

    var best: Cell? {
        cells.filter { $0.count >= 3 }.min(by: { $0.avg < $1.avg })
    }
}

// MARK: - View

struct HeatmapView: View {
    let hourlyData: [RateDataPoint]
    let isLoading:  Bool
    let pair:       CurrencyPair

    @State private var heatmap: HeatmapData? = nil

    private let weekdays   = [2, 3, 4, 5, 6]
    private let wdLabels   = [2: "월", 3: "화", 4: "수", 5: "목", 6: "금"]
    private let hours      = Array(8...18)

    var body: some View {
        Group {
            if isLoading {
                ProgressView("시간대 데이터 로딩 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hourlyData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("데이터를 불러올 수 없습니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let hm = heatmap {
                content(hm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: hourlyData.count) {
            guard !hourlyData.isEmpty else { return }
            let data = hourlyData
            let result = await Task.detached(priority: .userInitiated) {
                HeatmapData(data)
            }.value
            heatmap = result
        }
    }

    // MARK: Content

    private func content(_ hm: HeatmapData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            gridSection(hm)
            legendSection
            bestSection(hm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("환전 시간대 분석 (KST)", systemImage: "clock.badge.checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("최근 3개월 시간대별 평균 환율 편차 • 녹색일수록 환전에 유리한 시간")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func gridSection(_ hm: HeatmapData) -> some View {
        VStack(spacing: 2) {
            // Column headers
            HStack(spacing: 2) {
                Color.clear.frame(width: 34, height: 1)
                ForEach(weekdays, id: \.self) { wd in
                    Text(wdLabels[wd] ?? "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Data rows
            ForEach(hours, id: \.self) { h in
                HStack(spacing: 2) {
                    Text("\(h)h")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    ForEach(weekdays, id: \.self) { wd in
                        let cell = hm.cell(weekday: wd, hour: h)
                        cellView(cell)
                    }
                }
            }
        }
    }

    private func cellView(_ cell: HeatmapData.Cell?) -> some View {
        let color: Color = {
            guard let c = cell, c.count >= 3 else { return Color.primary.opacity(0.06) }
            let intensity = min(abs(c.deviation) / 0.003, 1.0)  // ±0.3% as full scale
            return c.deviation < 0
                ? .green.opacity(0.25 + intensity * 0.55)
                : .red.opacity(0.25 + intensity * 0.55)
        }()

        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .overlay {
                if let c = cell, c.count >= 3 {
                    Text(String(format: "%+.0f%%", c.deviation * 100))
                        .font(.system(size: 7.5))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
    }

    private var legendSection: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.7))
                    .frame(width: 12, height: 12)
                Text("낮은 환율 (유리)").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.red.opacity(0.7))
                    .frame(width: 12, height: 12)
                Text("높은 환율 (불리)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func bestSection(_ hm: HeatmapData) -> some View {
        if let best = hm.best {
            let label   = wdLabels[best.weekday] ?? ""
            let diffPct = abs(best.deviation) * 100
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.caption2).foregroundStyle(.yellow)
                Text("최적: \(label)요일 \(best.hour)시")
                    .font(.caption.weight(.semibold))
                Text(String(format: "(평균 대비 %.2f%% 낮음)", diffPct))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
