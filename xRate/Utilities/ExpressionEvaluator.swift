import Foundation

/// Tiny recursive-descent evaluator for the arithmetic the amount field
/// accepts: `+ - * /`, parentheses and unary minus.
///
/// Deliberately not `NSExpression`: `NSExpression(format:)` raises an
/// Objective-C exception that Swift cannot catch on malformed input like
/// "70*", which would crash the app between keystrokes. This evaluator is
/// total — it returns nil instead.
///
/// Evaluation is tolerant of half-typed input so that every keystroke still
/// yields a result: trailing operators are dropped and unclosed parentheses
/// are closed. Number tokens go through `ConverterModel.parse` so grouping
/// and decimal separators read the same inside an expression as outside it.
enum ExpressionEvaluator {
    /// Characters that make a string an expression rather than a plain number.
    private static let operatorCharacters: Set<Character> =
        ["+", "-", "*", "/", "(", ")", "×", "÷", "−", "–"]

    /// Characters accepted after normalization.
    private static let allowed: Set<Character> =
        Set("0123456789.,+-*/()")

    /// True when `s` contains an arithmetic operator or parenthesis — the
    /// signal to evaluate instead of calling `ConverterModel.parse`.
    static func containsOperator(_ s: String) -> Bool {
        s.contains { operatorCharacters.contains($0) }
    }

    /// Evaluates `s`, repairing half-typed input first. Returns nil when the
    /// text cannot be evaluated even after the repairs.
    static func evaluate(_ s: String) -> Double? {
        guard let cleaned = normalized(s) else { return nil }
        var parser = Parser(Array(cleaned))
        guard let value = parser.parseExpression(),
              parser.atEnd,
              value.isFinite else { return nil }
        return value
    }

    /// Strips whitespace, maps typographic operators onto ASCII, rejects any
    /// other character, then repairs a half-typed tail.
    private static func normalized(_ s: String) -> String? {
        var v = ""
        for ch in s where !ch.isWhitespace {
            let mapped: Character
            switch ch {
            case "×": mapped = "*"
            case "÷": mapped = "/"
            case "−", "–": mapped = "-"
            default: mapped = ch
            }
            guard allowed.contains(mapped) else { return nil }
            v.append(mapped)
        }

        // Half-typed tail: "70*" → "70", "2*(" → "2".
        while let last = v.last, last == "+" || last == "-"
                || last == "*" || last == "/" || last == "(" {
            v.removeLast()
        }
        if v.isEmpty { return nil }

        // Close what the user has not closed yet: "(40-12" → "(40-12)".
        let opens = v.reduce(0) { $0 + ($1 == "(" ? 1 : 0) }
        let closes = v.reduce(0) { $0 + ($1 == ")" ? 1 : 0) }
        guard opens >= closes else { return nil }
        v += String(repeating: ")", count: opens - closes)

        return v
    }

    /// expr    := term (("+" | "-") term)*
    /// term    := factor (("*" | "/") factor)*
    /// factor  := ("-" | "+")? primary
    /// primary := number | "(" expr ")"
    private struct Parser {
        private let chars: [Character]
        private var i = 0

        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { i >= chars.count }
        private var peek: Character? { atEnd ? nil : chars[i] }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek, op == "+" || op == "-" {
                i += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek, op == "*" || op == "/" {
                i += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                }
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            switch peek {
            case "-":
                i += 1
                guard let value = parseFactor() else { return nil }
                return -value
            case "+":
                i += 1
                return parseFactor()
            default:
                return parsePrimary()
            }
        }

        private mutating func parsePrimary() -> Double? {
            if peek == "(" {
                i += 1
                guard let value = parseExpression(), peek == ")" else { return nil }
                i += 1
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            let start = i
            while let c = peek, (c >= "0" && c <= "9") || c == "." || c == "," {
                i += 1
            }
            guard i > start else { return nil }
            return ConverterModel.parse(String(chars[start..<i]))
        }
    }
}
