import Foundation
import Observation

@Observable
@MainActor
final class ConverterModel {
    // MARK: persisted state

    var currencies: [Currency] {
        didSet { persistCurrencies() }
    }

    var baseCode: String {
        didSet { defaults.set(baseCode, forKey: Keys.baseCode) }
    }

    var amountText: String {
        didSet { defaults.set(amountText, forKey: Keys.amountText) }
    }

    var snapshot: RateSnapshot? {
        didSet { persistSnapshot() }
    }

    // MARK: transient state

    var availableCurrencies: [Currency] = []
    var errorMessage: String?
    var isLoading: Bool = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service: RatesService

    init(defaults: UserDefaults = .standard, service: RatesService = .shared) {
        self.defaults = defaults
        self.service = service

        let decoder = JSONDecoder()

        let loadedCurrencies: [Currency]
        if let data = defaults.data(forKey: Keys.currencies),
           let decoded = try? decoder.decode([Currency].self, from: data),
           !decoded.isEmpty {
            loadedCurrencies = decoded
        } else {
            loadedCurrencies = ConverterModel.defaultCurrencies
        }

        let storedBase = defaults.string(forKey: Keys.baseCode) ?? "HUF"
        let resolvedBase: String
        if loadedCurrencies.contains(where: { $0.code == storedBase }) {
            resolvedBase = storedBase
        } else {
            resolvedBase = loadedCurrencies.first?.code ?? "EUR"
        }

        let loadedAmount = defaults.string(forKey: Keys.amountText) ?? ""

        let loadedSnapshot: RateSnapshot?
        if let data = defaults.data(forKey: Keys.snapshot),
           let decoded = try? decoder.decode(RateSnapshot.self, from: data) {
            loadedSnapshot = decoded
        } else {
            loadedSnapshot = nil
        }

        self.currencies = loadedCurrencies
        self.baseCode = resolvedBase
        self.amountText = loadedAmount
        self.snapshot = loadedSnapshot
    }

    static let defaultCurrencies: [Currency] = [
        Currency(code: "HUF", name: "Hungarian Forint"),
        Currency(code: "EUR", name: "Euro"),
        Currency(code: "USD", name: "US Dollar"),
        Currency(code: "GBP", name: "British Pound"),
        Currency(code: "CAD", name: "Canadian Dollar"),
    ]

    enum Keys {
        static let currencies = "xrate.selectedCurrencies"
        static let baseCode = "xrate.baseCode"
        static let amountText = "xrate.amountText"
        static let snapshot = "xrate.snapshot"
    }

    private func persistCurrencies() {
        if let data = try? JSONEncoder().encode(currencies) {
            defaults.set(data, forKey: Keys.currencies)
        }
    }

    private func persistSnapshot() {
        guard let snapshot else {
            defaults.removeObject(forKey: Keys.snapshot)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshot)
        }
    }

    // MARK: computed

    var rates: [String: Double]? { snapshot?.rates }
    var lastUpdated: Date? { snapshot?.fetchedAt }

    var stale: Bool {
        guard let f = snapshot?.fetchedAt else { return true }
        return Date().timeIntervalSince(f) > 6 * 60 * 60
    }

    var amount: Double { Self.parse(amountText) }

    /// Locale-agnostic parser for amount input. Handles both "." and "," as
    /// decimal separators, strips Unicode whitespace, and uses a heuristic for
    /// a single separator (3 digits after = grouping, otherwise = decimal).
    /// For multi-separator strings the latest separator is the decimal and
    /// the rest is grouping.
    nonisolated static func parse(_ s: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }

        var v = String(trimmed.filter { !$0.isWhitespace })

        let lastComma = v.lastIndex(of: ",")
        let lastDot = v.lastIndex(of: ".")

        let lastSep: String.Index?
        switch (lastComma, lastDot) {
        case (nil, nil):
            lastSep = nil
        case (.some(let c), nil):
            lastSep = c
        case (nil, .some(let d)):
            lastSep = d
        case (.some(let c), .some(let d)):
            lastSep = c > d ? c : d
        }

        if let sepIdx = lastSep {
            let totalSeps = v.reduce(0) {
                $0 + (($1 == "," || $1 == ".") ? 1 : 0)
            }

            if totalSeps == 1 {
                let after = v.distance(from: v.index(after: sepIdx), to: v.endIndex)
                if after == 3 {
                    // Single separator with exactly 3 trailing digits → grouping.
                    v.remove(at: sepIdx)
                } else {
                    // Decimal. Normalize to period.
                    if v[sepIdx] != "." {
                        v.replaceSubrange(sepIdx...sepIdx, with: ".")
                    }
                }
            } else {
                // Multiple separators: latest is decimal, all others are grouping.
                let digitsAfter = v[v.index(after: sepIdx)...].filter(\.isNumber).count
                v.removeAll { $0 == "." || $0 == "," }
                if digitsAfter > 0, digitsAfter < v.count {
                    let insertAt = v.index(v.endIndex, offsetBy: -digitsAfter)
                    v.insert(".", at: insertAt)
                }
            }
        }

        return Double(v) ?? 0
    }

    func convert(amount: Double, from: String, to: String) -> Double? {
        guard let rates else { return nil }
        guard let fromRate = rates[from], let toRate = rates[to], fromRate > 0 else { return nil }
        if from == to { return amount }
        let inAnchor = amount / fromRate
        return inAnchor * toRate
    }

    /// Price of one unit of `code` expressed in `base` currency.
    func pricePerUnit(of code: String, in base: String) -> Double? {
        convert(amount: 1, from: code, to: base)
    }

    func setBase(_ code: String) {
        guard code != baseCode else { return }
        guard currencies.contains(where: { $0.code == code }) else { return }

        if let converted = convert(amount: amount, from: baseCode, to: code), amount != 0 {
            amountText = NumberFormatting.display(converted)
        }
        baseCode = code
    }

    func addCurrency(_ c: Currency) {
        guard !currencies.contains(where: { $0.code == c.code }) else { return }
        currencies.append(c)
    }

    func removeCurrency(_ code: String) {
        currencies.removeAll { $0.code == code }
        if baseCode == code {
            baseCode = currencies.first?.code ?? "EUR"
            amountText = ""
        }
    }

    // MARK: networking

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await service.fetchLatest()
            self.snapshot = snap
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func loadAvailable() async {
        do {
            let list = try await service.fetchAvailableCurrencies()
            self.availableCurrencies = list
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

}
