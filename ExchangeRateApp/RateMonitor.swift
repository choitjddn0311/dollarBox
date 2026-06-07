import Foundation
import Observation

@Observable
final class RateMonitor {
    var displayString: String = ""

    init() {
        if let saved = UserDefaults.standard.string(forKey: "menuBarDisplay"), !saved.isEmpty {
            displayString = saved
        }
        Task { @MainActor in await self.refresh() }
    }

    @MainActor
    func update(rate: Double, pair: CurrencyPair) {
        let str = "\(pair.label) ₩\(Int(rate * pair.displayMultiplier).formatted())"
        displayString = str
        UserDefaults.standard.set(str, forKey: "menuBarDisplay")
    }

    @MainActor
    func refresh() async {
        guard let rate = try? await ExchangeRateService.shared.fetchLatestRate(pair: .usdkrw) else { return }
        update(rate: rate.rate, pair: .usdkrw)
    }
}
