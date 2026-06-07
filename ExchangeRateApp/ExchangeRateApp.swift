import SwiftUI

@main
struct ExchangeRateApp: App {
    @State private var rateMonitor = RateMonitor()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(rateMonitor)
        }
        .defaultSize(width: 720, height: 620)

        MenuBarExtra {
            MenuBarView()
                .environment(rateMonitor)
        } label: {
            MenuBarLabel(display: rateMonitor.displayString, changePercent: rateMonitor.changePercent)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let display: String
    let changePercent: Double?

    var body: some View {
        if display.isEmpty {
            Image(systemName: "dollarsign.circle.fill")
        } else {
            HStack(spacing: 4) {
                Text(display)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if let pct = changePercent {
                    Text("\(pct >= 0 ? "▲" : "▼")\(abs(pct).formatted(.number.precision(.fractionLength(2))))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(pct >= 0 ? Color.green : Color.red)
                }
            }
        }
    }
}
