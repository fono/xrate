import SwiftUI

struct AddCurrencySheet: View {
    @Bindable var model: ConverterModel
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Currency")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TextField("Search by code or name", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if model.availableCurrencies.isEmpty {
                VStack {
                    ProgressView()
                    Text("Loading available currencies…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack {
                    Text(search.isEmpty ? "All currencies are already added." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { currency in
                    Button {
                        model.addCurrency(currency)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(Flag.emoji(forCurrencyCode: currency.code))
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currency.code).font(.headline)
                                Text(currency.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 440, idealHeight: 520)
        .task {
            if model.availableCurrencies.isEmpty {
                await model.loadAvailable()
            }
        }
    }

    private var filtered: [Currency] {
        let existing = Set(model.currencies.map(\.code))
        let candidates = model.availableCurrencies.filter { !existing.contains($0.code) }
        if search.isEmpty { return candidates }
        let q = search.lowercased()
        return candidates.filter {
            $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }
}
