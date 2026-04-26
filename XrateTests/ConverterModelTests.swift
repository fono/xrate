import XCTest
@testable import Xrate

@MainActor
final class ConverterModelTests: XCTestCase {

    private func makeModel(
        currencies: [Currency] = ConverterModel.defaultCurrencies,
        baseCode: String = "HUF",
        amountText: String = "20000"
    ) -> ConverterModel {
        let suiteName = "xrate.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let model = ConverterModel(defaults: defaults)
        model.currencies = currencies
        model.baseCode = baseCode
        model.amountText = amountText

        // Inject deterministic snapshot (rates against EUR, like Frankfurter).
        model.snapshot = RateSnapshot(
            base: "EUR",
            date: "2026-04-26",
            rates: [
                "EUR": 1.0,
                "HUF": 400.0,
                "USD": 1.10,
                "GBP": 0.85,
                "CAD": 1.50
            ],
            fetchedAt: Date()
        )

        return model
    }

    func testIdentityConversion() {
        let model = makeModel()
        XCTAssertEqual(model.convert(amount: 123.45, from: "EUR", to: "EUR"), 123.45)
        XCTAssertEqual(model.convert(amount: 0, from: "HUF", to: "USD"), 0)
    }

    func testHUFToUSDMatchesManualMath() throws {
        let model = makeModel()
        // 20000 HUF -> EUR -> USD; 20000 / 400 = 50 EUR; 50 * 1.10 = 55 USD
        let usd = try XCTUnwrap(model.convert(amount: 20000, from: "HUF", to: "USD"))
        XCTAssertEqual(usd, 55.0, accuracy: 0.0001)
    }

    func testReverseConversionRoundTrip() throws {
        let model = makeModel()
        let usd = try XCTUnwrap(model.convert(amount: 20000, from: "HUF", to: "USD"))
        let huf = try XCTUnwrap(model.convert(amount: usd, from: "USD", to: "HUF"))
        XCTAssertEqual(huf, 20000.0, accuracy: 0.0001)
    }

    func testPricePerUnit() throws {
        let model = makeModel()
        // 1 USD in HUF: rates[HUF]/rates[USD] = 400/1.10 ≈ 363.6363
        let perOne = try XCTUnwrap(model.pricePerUnit(of: "USD", in: "HUF"))
        XCTAssertEqual(perOne, 400.0 / 1.10, accuracy: 0.0001)
        // 1 HUF in USD ≈ 1/363.63 ≈ 0.00275
        let inverse = try XCTUnwrap(model.pricePerUnit(of: "HUF", in: "USD"))
        XCTAssertEqual(inverse, 1.10 / 400.0, accuracy: 0.000001)
    }

    func testSetBaseReExpressesAmount() {
        let model = makeModel(baseCode: "HUF", amountText: "20000")
        model.setBase("USD")
        XCTAssertEqual(model.baseCode, "USD")
        let amount = ConverterModel.parse(model.amountText)
        XCTAssertEqual(amount, 55.0, accuracy: 0.0001)
    }

    func testSetSameBaseIsNoOp() {
        let model = makeModel(baseCode: "HUF", amountText: "20000")
        model.setBase("HUF")
        XCTAssertEqual(model.baseCode, "HUF")
        XCTAssertEqual(model.amountText, "20000")
    }

    func testSetBaseToUnknownCurrencyIsIgnored() {
        let model = makeModel()
        model.setBase("XXX")
        XCTAssertEqual(model.baseCode, "HUF")
    }

    func testRemoveBaseFallsBackToFirstAndClearsAmount() {
        let model = makeModel()
        model.removeCurrency("HUF")
        XCTAssertEqual(model.baseCode, "EUR")
        XCTAssertEqual(model.amountText, "")
        XCTAssertFalse(model.currencies.contains(where: { $0.code == "HUF" }))
    }

    func testRemoveNonBaseLeavesBaseAlone() {
        let model = makeModel()
        model.removeCurrency("USD")
        XCTAssertEqual(model.baseCode, "HUF")
        XCTAssertEqual(model.amountText, "20000")
        XCTAssertFalse(model.currencies.contains(where: { $0.code == "USD" }))
    }

    func testAddCurrencyDoesNotDuplicate() {
        let model = makeModel()
        model.addCurrency(Currency(code: "USD", name: "US Dollar"))
        XCTAssertEqual(model.currencies.filter { $0.code == "USD" }.count, 1)

        model.addCurrency(Currency(code: "JPY", name: "Japanese Yen"))
        XCTAssertEqual(model.currencies.filter { $0.code == "JPY" }.count, 1)
    }

    func testParseAcceptsCommaAndPeriodAndWhitespace() {
        XCTAssertEqual(ConverterModel.parse("1,5"), 1.5)
        XCTAssertEqual(ConverterModel.parse("1.5"), 1.5)
        XCTAssertEqual(ConverterModel.parse(" 20 000 "), 20000)
        XCTAssertEqual(ConverterModel.parse(""), 0)
        XCTAssertEqual(ConverterModel.parse("abc"), 0)
    }

    func testParseTreatsLoneSeparatorWith3DigitsAsGrouping() {
        // "1,234" / "1.234": 4-digit shape with one separator → grouping.
        XCTAssertEqual(ConverterModel.parse("1,234"), 1234)
        XCTAssertEqual(ConverterModel.parse("1.234"), 1234)
        XCTAssertEqual(ConverterModel.parse("12,345"), 12345)
        // Lone separator with non-3 trailing digits → decimal.
        XCTAssertEqual(ConverterModel.parse("12,34"), 12.34)
        XCTAssertEqual(ConverterModel.parse("0.5"), 0.5)
    }

    func testParseHandlesMixedSeparators() {
        // US grouping + decimal.
        XCTAssertEqual(ConverterModel.parse("1,234.5"), 1234.5, accuracy: 0.0001)
        XCTAssertEqual(ConverterModel.parse("1,234,567.89"), 1234567.89, accuracy: 0.001)
        // EU grouping + decimal.
        XCTAssertEqual(ConverterModel.parse("1.234,5"), 1234.5, accuracy: 0.0001)
        XCTAssertEqual(ConverterModel.parse("1.234.567,89"), 1234567.89, accuracy: 0.001)
        // HU-style with non-breaking space grouping.
        XCTAssertEqual(ConverterModel.parse("1\u{00A0}234,5"), 1234.5, accuracy: 0.0001)
    }

    func testPersistenceRoundTrip() throws {
        let suiteName = "xrate.tests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let m1 = ConverterModel(defaults: defaults)
        m1.currencies = [
            Currency(code: "HUF", name: "Hungarian Forint"),
            Currency(code: "JPY", name: "Japanese Yen")
        ]
        m1.baseCode = "JPY"
        m1.amountText = "12345.6"
        m1.snapshot = RateSnapshot(
            base: "EUR",
            date: "2026-04-26",
            rates: ["EUR": 1.0, "HUF": 400.0, "JPY": 165.0],
            fetchedAt: Date()
        )

        let m2 = ConverterModel(defaults: defaults)
        XCTAssertEqual(m2.currencies.map(\.code), ["HUF", "JPY"])
        XCTAssertEqual(m2.baseCode, "JPY")
        XCTAssertEqual(m2.amountText, "12345.6")
        XCTAssertNotNil(m2.snapshot)
        XCTAssertEqual(m2.snapshot?.rates["HUF"], 400.0)
    }

    func testStaleSnapshot() {
        let model = makeModel()
        model.snapshot = RateSnapshot(
            base: "EUR",
            date: "2026-04-25",
            rates: ["EUR": 1.0, "HUF": 400.0],
            fetchedAt: Date(timeIntervalSinceNow: -7 * 60 * 60)
        )
        XCTAssertTrue(model.stale)

        model.snapshot = RateSnapshot(
            base: "EUR",
            date: "2026-04-26",
            rates: ["EUR": 1.0, "HUF": 400.0],
            fetchedAt: Date()
        )
        XCTAssertFalse(model.stale)
    }

    func testFlagsForKnownCurrencies() {
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "EUR"), "🇪🇺")
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "USD"), "🇺🇸")
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "HUF"), "🇭🇺")
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "GBP"), "🇬🇧")
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "CAD"), "🇨🇦")
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "JPY"), "🇯🇵")
        XCTAssertEqual(Flag.emoji(forCurrencyCode: "XAU"), "🥇")
    }
}
