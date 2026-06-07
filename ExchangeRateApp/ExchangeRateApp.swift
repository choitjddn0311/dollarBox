import SwiftUI

@main
struct ExchangeRateApp: App {
    @State private var rateMonitor = RateMonitor()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(rateMonitor)
        }
        .defaultSize(width: 720, height: 560)

        MenuBarExtra {
            MenuBarView()
                .environment(rateMonitor)
        } label: {
            MenuBarLabel(display: rateMonitor.displayString)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let display: String

    var body: some View {
        if display.isEmpty {
            Image(systemName: "dollarsign.circle.fill")
        } else {
            Text(display)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}
