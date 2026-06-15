import SwiftUI

struct AlertsView: View {
    let currentRates: [CurrencyPair: Double]

    @State private var alertManager = AlertManager.shared
    @State private var showAdd = false

    // Add form
    @State private var newPair: CurrencyPair = .usdkrw
    @State private var newRateText: String = ""
    @State private var newDirection: AlertDirection = .below

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            if alertManager.rules.isEmpty {
                emptyState
            } else {
                rulesList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showAdd) {
            addSheet.frame(width: 360, height: 260)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("설정된 알림")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                prepareForm()
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .glassEffect(in: Circle())
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text("환율 알림 없음")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("원하는 환율에 도달하면 알림을 받아보세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("알림 추가") {
                prepareForm()
                showAdd = true
            }
            .font(.caption.weight(.semibold))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rules List

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(alertManager.rules) { rule in
                    ruleRow(rule)
                }
            }
        }
    }

    private func ruleRow(_ rule: AlertRule) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(rule.firedAt != nil
                      ? Color.green
                      : (rule.isEnabled ? Color.accentColor : Color.secondary.opacity(0.35)))
                .frame(width: 7, height: 7)

            Text(rule.pair.label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.15), in: Capsule())

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("₩\(Int(rule.targetRate * rule.pair.displayMultiplier).formatted())")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(rule.direction.shortLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let fired = rule.firedAt {
                    Text("달성 · \(fired, format: .dateTime.month().day().hour().minute())")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.85))
                } else if !rule.isEnabled {
                    Text("비활성")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if rule.firedAt != nil {
                Button {
                    alertManager.reset(id: rule.id)
                } label: {
                    Text("재설정")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in alertManager.toggle(id: rule.id) }
                ))
                .labelsHidden()
                .controlSize(.small)
            }

            Button {
                alertManager.delete(id: rule.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add Sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("환율 알림 추가")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 16) {
                formRow("통화") {
                    Picker("", selection: $newPair) {
                        ForEach(CurrencyPair.allCases) { pair in
                            Text(pair.label).tag(pair)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: newPair) { _, pair in
                        if let rate = currentRates[pair] {
                            newRateText = "\(Int(rate * pair.displayMultiplier))"
                        }
                    }
                }

                formRow("환율") {
                    HStack(spacing: 4) {
                        Text("₩").foregroundStyle(.secondary)
                        TextField("1380", text: $newRateText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        if let rate = currentRates[newPair] {
                            Text("현재 ₩\(Int(rate * newPair.displayMultiplier).formatted())")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                formRow("조건") {
                    Picker("", selection: $newDirection) {
                        Text("이상 (오르면)").tag(AlertDirection.above)
                        Text("이하 (내리면)").tag(AlertDirection.below)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Spacer()

            HStack {
                Button("취소") { showAdd = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("추가") { commitAdd() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedRate == nil)
            }
        }
        .padding(24)
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            content()
        }
    }

    // MARK: - Helpers

    private var parsedRate: Double? {
        let cleaned = newRateText.replacingOccurrences(of: ",", with: "")
        guard let display = Double(cleaned), display > 0 else { return nil }
        return display / newPair.displayMultiplier
    }

    private func prepareForm() {
        newPair = .usdkrw
        newDirection = .below
        if let rate = currentRates[.usdkrw] {
            newRateText = "\(Int(rate * CurrencyPair.usdkrw.displayMultiplier))"
        } else {
            newRateText = ""
        }
    }

    private func commitAdd() {
        guard let raw = parsedRate else { return }
        alertManager.add(AlertRule(pair: newPair, targetRate: raw, direction: newDirection))
        showAdd = false
    }
}
