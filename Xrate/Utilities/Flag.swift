import Foundation

enum Flag {
    /// Returns a Unicode flag emoji for a given ISO-4217 currency code, by
    /// taking the first two characters as an ISO-3166 country code and
    /// composing them with regional-indicator scalars.
    static func emoji(forCurrencyCode code: String) -> String {
        let upper = code.uppercased()

        switch upper {
        case "EUR": return "🇪🇺"
        case "XAU": return "🥇"
        case "XAG": return "🥈"
        case "XDR", "XPD", "XPT": return "💱"
        default: break
        }

        let countryCode = String(upper.prefix(2))
        let scalars = countryCode.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            // ASCII A-Z = 65...90
            guard (65...90).contains(scalar.value) else { return nil }
            return UnicodeScalar(127397 + Int(scalar.value))
        }
        guard scalars.count == 2 else { return "💱" }
        return scalars.map { String($0) }.joined()
    }
}
