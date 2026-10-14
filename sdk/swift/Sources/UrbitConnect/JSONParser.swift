import Foundation

/// Bounded scanner rejects duplicates before a dictionary can discard them.
struct JSONParser {
    let bytes: [UInt8]
    let maxDepth: Int
    var index = 0
    mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    mutating func value(depth: Int) throws -> JSONValue {
        whitespace()
        guard index < bytes.count else { throw invalid("Expected a value") }
        switch bytes[index] {
        case 110: try literal("null"); return .null
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 34: return .string(try string())
        case 123:
            guard depth < maxDepth else { throw invalid("JSON depth exceeds \(maxDepth)") }
            index += 1; var fields: JSONObject = [:]
            if consume(125) { return .object(fields) }
            repeat {
                whitespace(); let key = try string()
                guard fields[key] == nil else { throw invalid("Duplicate object key") }
                guard consume(58) else { throw invalid("Expected colon") }
                fields[key] = try value(depth: depth + 1)
                if consume(125) { return .object(fields) }
                guard consume(44) else { throw invalid("Expected comma") }
            } while true
        case 91:
            guard depth < maxDepth else { throw invalid("JSON depth exceeds \(maxDepth)") }
            index += 1; var values: [JSONValue] = []
            if consume(93) { return .array(values) }
            repeat {
                values.append(try value(depth: depth + 1))
                if consume(93) { return .array(values) }
                guard consume(44) else { throw invalid("Expected comma") }
            } while true
        default: return .number(try number())
        }
    }
    private mutating func literal(_ text: String) throws {
        let expected = Array(text.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { throw invalid("Invalid literal") }
        index += expected.count
    }
    private mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == 34 else { throw invalid("Expected string") }
        let start = index; index += 1
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 {
                let value: String
                do { value = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                catch { throw invalid("Invalid string or Unicode escape") }
                guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else { throw invalid("U+0000 is outside the portable subset") }
                return value
            }
            if byte == 92 { index += 1 }
            else if byte < 32 { throw invalid("Unescaped control character") }
        }
        throw invalid("Unterminated string")
    }
    private mutating func number() throws -> String {
        let start = index
        while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        let raw = String(decoding: bytes[start..<index], as: UTF8.self)
        guard index - start <= 2048 else { throw invalid("Number spelling exceeds 2048 bytes") }
        guard raw.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw invalid("Invalid number") }
        let unsigned = raw.first == "-" ? String(raw.dropFirst()) : raw
        let parts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard let exponent = parts.count == 2 ? Int(parts[1]) : 0, (-1024...1024).contains(exponent) else { throw invalid("Exponent exceeds 1024") }
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        let fractional = mantissa.count == 2 ? mantissa[1].count : 0
        guard fractional <= 1024 else { throw invalid("Fraction exceeds 1024 digits") }
        var digits = mantissa.joined(); digits.removeAllLeadingZeros()
        if digits.isEmpty { return raw }
        let integerCount = digits.count + exponent - fractional
        guard integerCount <= 16 else { throw invalid("Number exceeds portable range") }
        if integerCount == 16 {
            let padded = digits + String(repeating: "0", count: max(0, 16 - digits.count))
            let whole = String(padded.prefix(16)), remainder = padded.dropFirst(16)
            guard whole < "9007199254740991" || (whole == "9007199254740991" && remainder.allSatisfy({ $0 == "0" })) else {
                throw invalid("Number exceeds portable range")
            }
        }
        return raw
    }
    private func invalid(_ reason: String) -> ConnectError { .invalidJSON(reason) }
}
private extension String {
    mutating func removeAllLeadingZeros() { self = String(drop(while: { $0 == "0" })) }
}
