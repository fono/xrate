import SwiftUI

struct ContentView: View {
    @Bindable var model: ConverterModel
    @State private var showingAddSheet = false
    @State private var focusedCode: String?

    var body: some View {
        VStack(spacing: 0) {
            if let msg = model.errorMessage {
                ErrorBanner(message: msg) {
                    model.errorMessage = nil
                }
            }

            List {
                ForEach(model.currencies) { currency in
                    CurrencyRow(
                        model: model,
                        currency: currency,
                        focusedCode: $focusedCode
                    )
                    .listRowBackground(
                        currency.code == model.baseCode
                            ? Color.gray.opacity(0.15)
                            : Color.clear
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            model.removeCurrency(currency.code)
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button("Set as Base Currency") { model.setBase(currency.code) }
                        Button("Remove", role: .destructive) {
                            model.removeCurrency(currency.code)
                        }
                    }
                }
            }
            .listStyle(.inset)

            StatusBar(model: model)
        }
        .navigationTitle("xRate")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isLoading)
                .help("Refresh exchange rates")
                .focusable(false)

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Currency", systemImage: "plus")
                }
                .help("Add a currency")
                .focusable(false)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCurrencySheet(model: model)
        }
        .task {
            if model.snapshot == nil {
                await model.refresh()
            } else if let lastUpdate = model.lastUpdated,
                      Date().timeIntervalSince(lastUpdate) > 30 * 60 {
                await model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xrateShowAddSheet)) { _ in
            showingAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .xrateRefresh)) { _ in
            Task { await model.refresh() }
        }
    }
}

struct StatusBar: View {
    @Bindable var model: ConverterModel

    var body: some View {
        HStack(spacing: 6) {
            if model.isLoading {
                ProgressView().controlSize(.mini)
                Text("Loading rates…")
            } else if let updated = model.lastUpdated {
                Text("Updated at: \(updated, format: .relative(presentation: .named, unitsStyle: .abbreviated))")
                    .help("Rates last updated: \(updated.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Rates not loaded")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}
