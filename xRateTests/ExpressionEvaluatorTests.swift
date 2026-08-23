import XCTest
@testable import xRate

final class ExpressionEvaluatorTests: XCTestCase {

    private func eval(_ s: String, _ expected: Double,
                      accuracy: Double = 1e-9,
                      file: StaticString = #filePath, line: UInt = #line) {
        guard let value = ExpressionEvaluator.evaluate(s) else {
            return XCTFail("expected \(s) to evaluate", file: file, line: line)
        }
        XCTAssertEqual(value, expected, accuracy: accuracy, file: file, line: line)
    }

    // MARK: the cases that motivated the feature

    func testMultiplication() {
        eval("70*1.27", 88.9)
    }

    func testParenthesizedDivision() {
        eval("(40-12)/6", 28.0 / 6.0)
    }

    // MARK: precedence and grouping

    func testPrecedence() {
        eval("2+3*4", 14)
        eval("2-3*4", -10)
        eval("10/2+3", 8)
    }

    func testParenthesesOverridePrecedence() {
        eval("(2+3)*4", 20)
        eval("2*(3+4)/7", 2)
        eval("((1+2)*(3+4))", 21)
    }

    func testUnaryMinus() {
        eval("-5+12", 7)
        eval("-(3+4)", -7)
        eval("3*-2", -6)
        eval("--4", 4)
    }

    func testTypographicOperators() {
        eval("70×1.27", 88.9)
        eval("84÷2", 42)
        eval("10−4", 6)
    }

    func testWhitespaceIsIgnored() {
        eval("  70 * 1.27  ", 88.9)
        eval("70\u{00A0}*\u{00A0}2", 140)
    }

    // MARK: mid-typing tolerance

    func testTrailingOperatorIsDropped() {
        eval("70*", 70)
        eval("5+", 5)
        eval("2*(", 2)
        eval("(40-12)/", 28)
    }

    func testUnclosedParenthesesAreClosed() {
        eval("(40-12", 28)
        eval("((1+2", 3)
        eval("2*(3+4", 14)
    }

    func testEveryKeystrokeOfAnExpressionEvaluates() {
        let expected: [String: Double] = [
            "7": 7, "70": 70, "70*": 70, "70*1": 70,
            "70*1.": 70, "70*1.2": 84, "70*1.27": 88.9
        ]
        for (text, value) in expected {
            eval(text, value, accuracy: 1e-9)
        }

        for prefix in ["(", "(4", "(40", "(40-", "(40-1", "(40-12", "(40-12)", "(40-12)/", "(40-12)/6"] {
            if prefix == "(" {
                // Nothing left after repair.
                XCTAssertNil(ExpressionEvaluator.evaluate(prefix))
            } else {
                XCTAssertNotNil(ExpressionEvaluator.evaluate(prefix), "\(prefix) should evaluate")
            }
        }
    }

    // MARK: rejection

    func testUnevaluableInputReturnsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("1/0"))
        XCTAssertNil(ExpressionEvaluator.evaluate(")("))
        XCTAssertNil(ExpressionEvaluator.evaluate("(1+2))"))
        XCTAssertNil(ExpressionEvaluator.evaluate("abc"))
        XCTAssertNil(ExpressionEvaluator.evaluate("2^10"))
        XCTAssertNil(ExpressionEvaluator.evaluate("50%"))
        XCTAssertNil(ExpressionEvaluator.evaluate(""))
        XCTAssertNil(ExpressionEvaluator.evaluate("   "))
    }

    // MARK: number tokens reuse ConverterModel.parse

    func testNumberTokensFollowTheFieldsGroupingRules() {
        // parse("1.234") is 1234 (one separator, three trailing digits), so an
        // expression must read it the same way the plain field does.
        eval("1.234*2", 2468)
        eval("1,5*2", 3)
        eval("1.234,5+0.5", 1235)
    }

    // MARK: containsOperator

    func testContainsOperator() {
        XCTAssertTrue(ExpressionEvaluator.containsOperator("70*1.27"))
        XCTAssertTrue(ExpressionEvaluator.containsOperator("(40-12)/6"))
        XCTAssertTrue(ExpressionEvaluator.containsOperator("-5"))
        XCTAssertFalse(ExpressionEvaluator.containsOperator("1 234"))
        XCTAssertFalse(ExpressionEvaluator.containsOperator("1.234"))
        XCTAssertFalse(ExpressionEvaluator.containsOperator("1,5"))
        XCTAssertFalse(ExpressionEvaluator.containsOperator(""))
    }
}
