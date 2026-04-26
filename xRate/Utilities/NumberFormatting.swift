import Foundation

enum NumberFormatting {
    static let display: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    static let perUnit: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    static func display(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return display.string(from: NSNumber(value: value)) ?? ""
    }

    static func perUnit(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return perUnit.string(from: NSNumber(value: value)) ?? ""
    }
}
