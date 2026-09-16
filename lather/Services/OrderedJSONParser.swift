import Foundation

/// A JSON value that preserves object key order — `JSONSerialization` decodes
/// objects into `[String: Any]`, which loses the order the user typed keys
/// in, so every XML round trip would shuffle fields around.
indirect enum JSONValue {
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    case object([(String, JSONValue)])
    case array([JSONValue])
}

/// A small recursive-descent JSON parser — used instead of `JSONSerialization`
/// specifically where key order matters (`SOAPTranslator.jsonToXML`).
/// `JSONValidator`/`JSONSerialization` remain the authority on whether JSON
/// is well-formed; this assumes valid input.
enum OrderedJSONParser {
    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ text: String) throws -> JSONValue {
        var chars = Array(text)
        var index = 0
        let value = try parseValue(&chars, &index)
        skipWhitespace(&chars, &index)
        guard index == chars.count else {
            throw ParseError(message: "Unexpected trailing content after JSON value.")
        }
        return value
    }

    private static func parseValue(_ chars: inout [Character], _ index: inout Int) throws -> JSONValue {
        skipWhitespace(&chars, &index)
        guard index < chars.count else { throw ParseError(message: "Unexpected end of JSON.") }

        switch chars[index] {
        case "{": return try parseObject(&chars, &index)
        case "[": return try parseArray(&chars, &index)
        case "\"": return .string(try parseString(&chars, &index))
        case "t": try expect("true", &chars, &index); return .bool(true)
        case "f": try expect("false", &chars, &index); return .bool(false)
        case "n": try expect("null", &chars, &index); return .null
        default: return .number(try parseNumber(&chars, &index))
        }
    }

    private static func parseObject(_ chars: inout [Character], _ index: inout Int) throws -> JSONValue {
        index += 1 // consume '{'
        var fields: [(String, JSONValue)] = []

        skipWhitespace(&chars, &index)
        if index < chars.count, chars[index] == "}" {
            index += 1
            return .object(fields)
        }

        while true {
            skipWhitespace(&chars, &index)
            guard index < chars.count, chars[index] == "\"" else {
                throw ParseError(message: "Expected a string key.")
            }
            let key = try parseString(&chars, &index)

            skipWhitespace(&chars, &index)
            guard index < chars.count, chars[index] == ":" else {
                throw ParseError(message: "Expected ':' after key.")
            }
            index += 1

            let value = try parseValue(&chars, &index)
            fields.append((key, value))

            skipWhitespace(&chars, &index)
            guard index < chars.count else { throw ParseError(message: "Unterminated object.") }
            if chars[index] == "," {
                index += 1
                continue
            }
            if chars[index] == "}" {
                index += 1
                break
            }
            throw ParseError(message: "Expected ',' or '}'.")
        }

        return .object(fields)
    }

    private static func parseArray(_ chars: inout [Character], _ index: inout Int) throws -> JSONValue {
        index += 1 // consume '['
        var items: [JSONValue] = []

        skipWhitespace(&chars, &index)
        if index < chars.count, chars[index] == "]" {
            index += 1
            return .array(items)
        }

        while true {
            items.append(try parseValue(&chars, &index))
            skipWhitespace(&chars, &index)
            guard index < chars.count else { throw ParseError(message: "Unterminated array.") }
            if chars[index] == "," {
                index += 1
                continue
            }
            if chars[index] == "]" {
                index += 1
                break
            }
            throw ParseError(message: "Expected ',' or ']'.")
        }

        return .array(items)
    }

    private static func parseString(_ chars: inout [Character], _ index: inout Int) throws -> String {
        index += 1 // consume opening quote
        var result = ""
        while index < chars.count, chars[index] != "\"" {
            if chars[index] == "\\" {
                index += 1
                guard index < chars.count else { throw ParseError(message: "Unterminated escape sequence.") }
                switch chars[index] {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "u":
                    guard index + 4 < chars.count else { throw ParseError(message: "Invalid unicode escape.") }
                    let hex = String(chars[(index + 1)...(index + 4)])
                    guard let scalarValue = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(scalarValue) else {
                        throw ParseError(message: "Invalid unicode escape '\\u\(hex)'.")
                    }
                    result.append(Character(scalar))
                    index += 4
                default:
                    throw ParseError(message: "Invalid escape sequence '\\\(chars[index])'.")
                }
                index += 1
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        guard index < chars.count else { throw ParseError(message: "Unterminated string.") }
        index += 1 // consume closing quote
        return result
    }

    private static func parseNumber(_ chars: inout [Character], _ index: inout Int) throws -> String {
        let start = index
        while index < chars.count, "-+.eE0123456789".contains(chars[index]) {
            index += 1
        }
        guard index > start else { throw ParseError(message: "Expected a value.") }
        return String(chars[start..<index])
    }

    private static func expect(_ literal: String, _ chars: inout [Character], _ index: inout Int) throws {
        for expected in literal {
            guard index < chars.count, chars[index] == expected else {
                throw ParseError(message: "Expected '\(literal)'.")
            }
            index += 1
        }
    }

    private static func skipWhitespace(_ chars: inout [Character], _ index: inout Int) {
        while index < chars.count, chars[index] == " " || chars[index] == "\t" || chars[index] == "\n" || chars[index] == "\r" {
            index += 1
        }
    }
}
