import Foundation

struct RateSnapshot: Codable, Sendable, Equatable {
    let base: String
    let date: String
    let rates: [String: Double]
    let fetchedAt: Date

    var allCodes: Set<String> {
        Set(rates.keys).union([base])
    }
}
