import Foundation
import UserNotifications

enum AlertDirection: String, Codable {
    case above, below
    var shortLabel: String { self == .above ? "이상" : "이하" }
    var fullLabel: String { self == .above ? "이상 (오르면)" : "이하 (내리면)" }
}

struct AlertRule: Codable, Identifiable {
    var id: UUID = UUID()
    var pair: CurrencyPair
    var targetRate: Double  // raw rate (before displayMultiplier)
    var direction: AlertDirection
    var isEnabled: Bool = true
    var firedAt: Date? = nil
}

@Observable
final class AlertManager {
    static let shared = AlertManager()
    private(set) var rules: [AlertRule] = []
    private let storageKey = "alertRules_v1"

    private init() { load() }

    func check(rate: Double, for pair: CurrencyPair) {
        var dirty = false
        for i in rules.indices {
            guard rules[i].pair == pair, rules[i].isEnabled, rules[i].firedAt == nil else { continue }
            let hit = rules[i].direction == .above
                ? rate >= rules[i].targetRate
                : rate <= rules[i].targetRate
            guard hit else { continue }
            rules[i].firedAt = Date()
            rules[i].isEnabled = false
            sendNotification(rules[i], current: rate)
            dirty = true
        }
        if dirty { save() }
    }

    func add(_ rule: AlertRule) { rules.append(rule); save() }

    func delete(id: UUID) { rules.removeAll { $0.id == id }; save() }

    func toggle(id: UUID) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].isEnabled.toggle()
        if rules[i].isEnabled { rules[i].firedAt = nil }
        save()
    }

    func reset(id: UUID) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].firedAt = nil
        rules[i].isEnabled = true
        save()
    }

    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(_ rule: AlertRule, current: Double) {
        let m = rule.pair.displayMultiplier
        let content = UNMutableNotificationContent()
        content.title = "환율 알림 — \(rule.pair.headerText)"
        content.body = "₩\(Int(rule.targetRate * m).formatted()) \(rule.direction.shortLabel) 달성 · 현재 ₩\(Int(current * m).formatted())"
        content.sound = .default
        let req = UNNotificationRequest(identifier: rule.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) else { return }
        rules = decoded
    }
}
