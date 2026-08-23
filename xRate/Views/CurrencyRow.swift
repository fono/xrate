import SwiftUI

struct CurrencyRow: View {
    @Bindable var model: ConverterModel
    let currency: Currency
    @Binding var focusedCode: String?

    private var isBase: Bool { currency.code == model.baseCode }

    /// Numeric value to show in this row's input — the model's `amount`
    /// expressed in this row's currency.
    private var displayValue: Double {
        if isBase { return model.amount }
        return model.convert(amount: model.amount, from: model.baseCode, to: currency.code) ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Flag.emoji(forCurrencyCode: currency.code))
                    .font(.system(size: 28))
                Text(currency.code)
                    .font(.headline)
                    .monospacedDigit()
            }
            .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                AmountField(
                    displayValue: displayValue,
                    isFocused: focusedCode == currency.code,
                    onUserEdit: { text in
                        model.applyInput(text, from: currency.code)
                    },
                    onClickFocus: { switchHere() },
                    onTab: { reverse in advanceFocus(reverse: reverse) }
                )

                HStack(alignment: .top) {
                    Text(currency.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    rateInfo
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rateInfo: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if isBase {
                Text("Base currency")
                if let result = model.expressionResult {
                    Text("= \(Self.resultText(result))")
                } else {
                    Text(" ").hidden()
                }
            } else if let perOne = model.pricePerUnit(of: currency.code, in: model.baseCode),
                      let inverse = model.pricePerUnit(of: model.baseCode, in: currency.code) {
                Text("1 \(currency.code) = \(NumberFormatting.perUnit(perOne)) \(model.baseCode)")
                Text("1 \(model.baseCode) = \(NumberFormatting.perUnit(inverse)) \(currency.code)")
            } else {
                Text("Rate unavailable")
                Text(" ").hidden()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// `ConverterModel.format` renders 0 as "" by design (empty field), which
    /// would leave a bare "= " here.
    private static func resultText(_ value: Double) -> String {
        let formatted = ConverterModel.format(value)
        return formatted.isEmpty ? "0" : formatted
    }

    /// Make this row the base currency and the focused row, synchronously.
    private func switchHere() {
        if model.baseCode != currency.code {
            model.setBase(currency.code)
        }
        if focusedCode != currency.code {
            focusedCode = currency.code
        }
    }

    private func advanceFocus(reverse: Bool) {
        let codes = model.currencies.map(\.code)
        guard !codes.isEmpty,
              let idx = codes.firstIndex(of: currency.code) else { return }
        let nextIdx = reverse
            ? (idx - 1 + codes.count) % codes.count
            : (idx + 1) % codes.count
        let nextCode = codes[nextIdx]
        // setBase BEFORE focusedCode change so both updates batch into a
        // single SwiftUI render pass.
        if model.baseCode != nextCode {
            model.setBase(nextCode)
        }
        focusedCode = nextCode
    }
}
