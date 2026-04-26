import SwiftUI

struct CurrencyRow: View {
    @Bindable var model: ConverterModel
    let currency: Currency
    @Binding var focusedCode: String?

    private var isBase: Bool { currency.code == model.baseCode }

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
                    text: textBinding,
                    isFocused: focusedCode == currency.code,
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
                Text(" ").hidden()
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

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if isBase { return model.amountText }
                guard let value = model.convert(amount: model.amount, from: model.baseCode, to: currency.code),
                      value != 0 else { return "" }
                return NumberFormatting.display(value)
            },
            set: { newValue in
                if model.baseCode != currency.code {
                    model.setBase(currency.code)
                }
                model.amountText = newValue
            }
        )
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
