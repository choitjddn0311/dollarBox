import SwiftUI

struct JournalView: View {
    var currentRates: [CurrencyPair: Double]

    private let journal = TradeJournalService.shared
    @State private var showAdd = false
    @State private var editingEntry: TradeEntry?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if journal.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
            addButton
        }
        .sheet(isPresented: $showAdd) {
            EntryFormView(currentRates: currentRates) { journal.add($0) }
        }
        .sheet(item: $editingEntry) { entry in
            EntryFormView(existing: entry, currentRates: currentRates) { journal.update($0) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("환전 기록이 없어요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("+ 버튼으로 첫 기록을 남겨보세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(journal.entries) { entry in
                    EntryRow(entry: entry, currentRate: currentRates[entry.pair])
                        .contentShape(Rectangle())
                        .onTapGesture { editingEntry = entry }
                        .contextMenu {
                            Button(role: .destructive) {
                                journal.delete(id: entry.id)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(in: Circle())
    }
}

// MARK: - Entry Row

private struct EntryRow: View {
    let entry: TradeEntry
    let currentRate: Double?

    private var displayRate: Double { entry.rate * entry.pair.displayMultiplier }

    private var rateDiff: Double? {
        guard let current = currentRate else { return nil }
        return current - entry.rate
    }

    private var ratePct: Double? {
        guard let diff = rateDiff, entry.rate > 0 else { return nil }
        return (diff / entry.rate) * 100
    }

    private var krwPnl: Double? {
        guard let diff = rateDiff, let amount = entry.baseAmount else { return nil }
        return diff * amount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.pair.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color.accentColor)
                    Text(entry.date, style: .date)
                        .font(.subheadline.weight(.medium))
                }
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("₩\(displayRate.formatted(.number.precision(.fractionLength(2))))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if let amount = entry.baseAmount {
                    Text("\(entry.pair.symbol)\(amount.formatted(.number.precision(.fractionLength(0))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let pct = ratePct {
                let positive = pct >= 0
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: positive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                        Text("\(positive ? "+" : "")\(pct.formatted(.number.precision(.fractionLength(2))))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(positive ? .green : .red)

                    if let pnl = krwPnl {
                        Text("\(pnl >= 0 ? "+" : "")₩\(Int(pnl).formatted())")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle((pnl >= 0 ? Color.green : Color.red).opacity(0.8))
                    }
                }
                .frame(minWidth: 76, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Entry Form

struct EntryFormView: View {
    var existing: TradeEntry? = nil
    var currentRates: [CurrencyPair: Double]
    var onSave: (TradeEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = .now
    @State private var pair: CurrencyPair = .usdkrw
    @State private var rateText: String = ""
    @State private var amountText: String = ""
    @State private var note: String = ""

    private var isEditing: Bool { existing != nil }
    private var parsedDisplayRate: Double? {
        Double(rateText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "기록 수정" : "환전 기록 추가")
                .font(.title3.bold())
                .padding(.bottom, 20)

            VStack(spacing: 14) {
                formRow("통화") {
                    Picker("", selection: $pair) {
                        ForEach(CurrencyPair.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: pair) { _, newPair in
                        guard !isEditing else { return }
                        rateText = prefillRate(for: newPair)
                    }
                }

                formRow("날짜") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                formRow(pair.displayUnitLabel + " =") {
                    HStack(spacing: 4) {
                        Text("₩").foregroundStyle(.secondary)
                        TextField("환율", text: $rateText)
                            .textFieldStyle(.plain)
                            .monospacedDigit()
                    }
                }

                formRow("금액 (선택)") {
                    HStack(spacing: 4) {
                        Text(pair.symbol).foregroundStyle(.secondary)
                        TextField("외화 금액", text: $amountText)
                            .textFieldStyle(.plain)
                            .monospacedDigit()
                    }
                }

                formRow("메모 (선택)") {
                    TextField("메모", text: $note)
                        .textFieldStyle(.plain)
                }
            }

            Button(action: save) {
                Text("저장")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .disabled(parsedDisplayRate == nil)
            .padding(.top, 20)

            Button("취소") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
        .padding(24)
        .frame(width: 360)
        .onAppear(perform: populate)
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func prefillRate(for p: CurrencyPair) -> String {
        guard let raw = currentRates[p] else { return "" }
        return (raw * p.displayMultiplier).formatted(.number.precision(.fractionLength(2)))
    }

    private func populate() {
        if let e = existing {
            date = e.date
            pair = e.pair
            rateText = (e.rate * e.pair.displayMultiplier)
                .formatted(.number.precision(.fractionLength(2)))
            amountText = e.baseAmount
                .map { $0.formatted(.number.precision(.fractionLength(0))) } ?? ""
            note = e.note
        } else {
            rateText = prefillRate(for: pair)
        }
    }

    private func save() {
        guard let displayRate = parsedDisplayRate else { return }
        let entry = TradeEntry(
            id: existing?.id ?? UUID(),
            date: date,
            pair: pair,
            rate: displayRate / pair.displayMultiplier,
            baseAmount: Double(amountText.replacingOccurrences(of: ",", with: "")),
            note: note
        )
        onSave(entry)
        dismiss()
    }
}
