import Foundation

actor RatesService {
    static let shared = RatesService()

    enum ServiceError: LocalizedError {
        case http(Int)
        case decode
        case empty

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Server error (\(code))."
            case .decode: return "Could not understand the server response."
            case .empty: return "The server returned no rate data."
            }
        }
    }

    private struct RateRow: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Double
    }

    private struct CurrencyRow: Decodable {
        let isoCode: String
        let name: String

        enum CodingKeys: String, CodingKey {
            case isoCode = "iso_code"
            case name
        }
    }

    private let baseURL = URL(string: "https://api.frankfurter.dev/v2/")!

    func fetchLatest() async throws -> RateSnapshot {
        let url = baseURL.appendingPathComponent("rates")
        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.http(http.statusCode)
        }

        let rows = try JSONDecoder().decode([RateRow].self, from: data)
        guard let first = rows.first else { throw ServiceError.empty }

        var rates: [String: Double] = [first.base: 1.0]
        for row in rows {
            rates[row.quote] = row.rate
        }

        return RateSnapshot(
            base: first.base,
            date: first.date,
            rates: rates,
            fetchedAt: Date()
        )
    }

    func fetchAvailableCurrencies() async throws -> [Currency] {
        let url = baseURL.appendingPathComponent("currencies")
        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.http(http.statusCode)
        }

        let rows = try JSONDecoder().decode([CurrencyRow].self, from: data)
        return rows
            .map { Currency(code: $0.isoCode, name: $0.name) }
            .sorted { $0.code < $1.code }
    }
}
