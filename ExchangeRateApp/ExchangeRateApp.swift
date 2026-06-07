import SwiftUI

@main
struct ExchangeRateApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .defaultSize(width: 720, height: 560)

        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @AppStorage("menuBarDisplay") private var display: String = ""

    var body: some View {
        if display.isEmpty {
            Image(systemName: "dollarsign.circle.fill")
        } else {
            Text(display)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}
