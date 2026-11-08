import Foundation

// Quick-bar arithmetic: + − × ÷ % ^, parentheses, unary minus, decimals, and
// thousands commas. A tiny recursive-descent parser rather than NSExpression,
// which raises an uncatchable ObjC exception on malformed input — and this
// parses whatever the user types. Pure, so the swiftc harness covers it.
enum Calculator {
    /// The value of `input`, or nil when it isn't a complete arithmetic
    /// expression (plain words, a lone number, trailing operator, ÷0…).
    static func evaluate(_ input: String) -> Double? {
        let normalized = input
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "")
            .filter { !$0.isWhitespace }
        // A lone number isn't a calculation — let the bar search it instead.
        guard normalized.contains(where: { "+-*/%^(".contains($0) }) else { return nil }
        var p = Parser(chars: Array(normalized))
        guard let v = p.expression(), p.i == p.chars.count, v.isFinite else { return nil }
        return v
    }

    /// "42", "3.5", "0.3333333333" — integers without ".0", else ≤10 places.
    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        var s = String(format: "%.10f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        // expression := term (('+'|'-') term)*
        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        // term := unary (('*'|'/'|'%') unary)*
        mutating func term() -> Double? {
            guard var v = unary() else { return nil }
            while i < chars.count, "*/%".contains(chars[i]) {
                let op = chars[i]; i += 1
                guard let r = unary() else { return nil }
                switch op {
                case "*": v *= r
                case "/": guard r != 0 else { return nil }; v /= r
                default: guard r != 0 else { return nil }; v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }

        // unary := '-' unary | power   — so -3^2 = -(3^2), as on a calculator
        mutating func unary() -> Double? {
            if i < chars.count, chars[i] == "-" { i += 1; return unary().map { -$0 } }
            return power()
        }

        // power := primary ('^' unary)?   (right-associative: 2^3^2 = 2^9)
        mutating func power() -> Double? {
            guard let base = primary() else { return nil }
            guard i < chars.count, chars[i] == "^" else { return base }
            i += 1
            guard let exp = unary() else { return nil }
            return pow(base, exp)
        }

        // primary := number | '(' expression ')'
        mutating func primary() -> Double? {
            guard i < chars.count else { return nil }
            if chars[i] == "(" {
                i += 1
                guard let v = expression(), i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            return Double(String(chars[start..<i]))
        }
    }
}
