import WidgetKit
import SwiftUI

struct ExchangeRateWidget: Widget {
    let kind = "ExchangeRateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExchangeRateProvider()) { entry in
            ExchangeRateWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("USD/KRW")
        .description("실시간 달러-원 환율을 표시합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ExchangeRateWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExchangeRateWidget()
    }
}
