import SwiftUI

struct SettingsView: View {
    @AppStorage("showMA7")             private var showMA7             = true
    @AppStorage("showMA30")            private var showMA30            = true
    @AppStorage("showBollingerBands")  private var showBollingerBands  = false
    @AppStorage("showRSI")             private var showRSI             = false
    @AppStorage("showPrediction")      private var showPrediction      = false
    @AppStorage("showWeekGauge")       private var showWeekGauge       = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("차트 지표")
                .font(.title3.bold())
                .padding(.bottom, 20)

            section("이동평균선") {
                row("MA 7일",   sub: "단기 추세",              isOn: $showMA7)
                row("MA 30일",  sub: "중기 추세 (1Y·5Y 전용)",  isOn: $showMA30)
            }

            Divider().padding(.vertical, 14)

            section("기술적 지표") {
                row("볼린저 밴드", sub: "20일 기준 변동 구간",        isOn: $showBollingerBands)
                row("RSI (14)",   sub: "과매수 70↑  ·  과매도 30↓", isOn: $showRSI)
            }

            Divider().padding(.vertical, 14)

            section("추세 분석") {
                row("예측선",      sub: "선형 회귀 기반 단기 추세 연장", isOn: $showPrediction)
                row("52W 게이지", sub: "52주 최고/최저 범위 표시",       isOn: $showWeekGauge)
            }

            Divider().padding(.vertical, 14)

            Text("1W 기간은 데이터 부족으로 MA·볼린저·RSI·예측선이 표시되지 않습니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 290)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ title: String, sub: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
