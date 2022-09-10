//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

extension RNJSONSerialization {
    public struct WritingOptions : OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let prettyPrinted = WritingOptions(rawValue: 1 << 0)
        public static let sortedKeys = WritingOptions(rawValue: 1 << 1)
        public static let fragmentsAllowed = WritingOptions(rawValue: 1 << 2)
        public static let withoutEscapingSlashes = WritingOptions(rawValue: 1 << 3)
    }
}

extension RNJSONSerialization {
    // Structures with container nesting deeper than this limit are not valid if passed in in-memory for validation, nor if they are read during deserialization.
    // This matches Darwin Foundation's validation behavior.
    fileprivate static let maximumRecursionDepth = 512
}


/* A class for converting JSON to Foundation/Swift objects and converting Foundation/Swift objects to JSON.

   An object that may be converted to JSON must have the following properties:
    - Top level object is a `Swift.Array` or `Swift.Dictionary`
    - All objects are `Swift.String`, `Foundation.NSNumber`, `Swift.Array`, `Swift.Dictionary`,
      or `Foundation.NSNull`
    - All dictionary keys are `Swift.String`s
    - `NSNumber`s are not NaN or infinity
*/

open class RNJSONSerialization : NSObject {}

//MARK: - Encoding Detection

private extension RNJSONSerialization {
    /// Detect the encoding format of the NSData contents
    static func detectEncoding(_ bytes: UnsafeRawBufferPointer) -> (String.Encoding, Int) {
        // According to RFC8259, the text encoding in JSON must be UTF8 in nonclosed systems
        // https://tools.ietf.org/html/rfc8259#section-8.1
        // However, since Darwin Foundation supports utf16 and utf32, so should Swift Foundation.

        // First let's check if we can determine the encoding based on a leading Byte Ordering Mark
        // (BOM).
        if bytes.count >= 4 {
            if bytes.starts(with: Self.utf8BOM) {
                return (.utf8, 3)
            }
            if bytes.starts(with: Self.utf32BigEndianBOM) {
                return (.utf32BigEndian, 4)
            }
            if bytes.starts(with: Self.utf32LittleEndianBOM) {
                return (.utf32LittleEndian, 4)
            }
            if bytes.starts(with: [0xFF, 0xFE]) {
                return (.utf16LittleEndian, 2)
            }
            if bytes.starts(with: [0xFE, 0xFF]) {
                return (.utf16BigEndian, 2)
            }
        }

        // If there is no BOM present, we might be able to determine the encoding based on
        // occurences of null bytes.
        if bytes.count >= 4 {
            switch (bytes[0], bytes[1], bytes[2], bytes[3]) {
            case (0, 0, 0, _):
                return (.utf32BigEndian, 0)
            case (_, 0, 0, 0):
                return (.utf32LittleEndian, 0)
            case (0, _, 0, _):
                return (.utf16BigEndian, 0)
            case (_, 0, _, 0):
                return (.utf16LittleEndian, 0)
            default:
                break
            }
        }
        else if bytes.count >= 2 {
            switch (bytes[0], bytes[1]) {
            case (0, _):
                return (.utf16BigEndian, 0)
            case (_, 0):
                return (.utf16LittleEndian, 0)
            default:
                break
            }
        }
        return (.utf8, 0)
    }

    static func parseBOM(_ bytes: UnsafeRawBufferPointer) -> (encoding: String.Encoding, skipLength: Int)? {

        return nil
    }

    // These static properties don't look very nice, but we need them to
    // workaround: https://bugs.swift.org/browse/SR-14102
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf32BigEndianBOM: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]
    private static let utf32LittleEndianBOM: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
    private static let utf16BigEndianBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16LittleEndianBOM: [UInt8] = [0xFE, 0xFF]
}

//MARK: - JSONSerializer
private struct JSONWriter {

    var indent = 0
    let pretty: Bool
    let sortedKeys: Bool
    let withoutEscapingSlashes: Bool
    let writer: (String?) -> Void

    init(options: RNJSONSerialization.WritingOptions, writer: @escaping (String?) -> Void) {
        pretty = options.contains(.prettyPrinted)
        sortedKeys = options.contains(.sortedKeys)
        withoutEscapingSlashes = options.contains(.withoutEscapingSlashes)
        self.writer = writer
    }

    mutating func serializeJSON(_ object: Any?) throws {

        let toSerialize = object

//        if let number = toSerialize as? _NSNumberCastingWithoutBridging {
//            toSerialize = number._swiftValueOfOptimalType
//        }

        guard let obj = toSerialize else {
            try serializeNull()
            return
        }

        // For better performance, the most expensive conditions to evaluate should be last.
        switch (obj) {
        case let str as String:
            try serializeString(str)
        case let boolValue as Bool:
            writer(boolValue.description)
        case let num as Int:
            writer(num.description)
        case let num as Int8:
            writer(num.description)
        case let num as Int16:
            writer(num.description)
        case let num as Int32:
            writer(num.description)
        case let num as Int64:
            writer(num.description)
        case let num as UInt:
            writer(num.description)
        case let num as UInt8:
            writer(num.description)
        case let num as UInt16:
            writer(num.description)
        case let num as UInt32:
            writer(num.description)
        case let num as UInt64:
            writer(num.description)
        case let array as Array<Any?>:
            try serializeArray(array)
        case let dict as Dictionary<AnyHashable, Any?>:
            try serializeDictionary(dict)
        case let num as Float:
            try serializeFloat(num)
        case let num as Double:
            try serializeFloat(num)
        case let num as Decimal:
            writer(num.description)
        case let num as NSDecimalNumber:
            writer(num.description)
        case is NSNull:
            try serializeNull()
//        case _ where __SwiftValue.store(obj) is NSNumber:
//            let num = __SwiftValue.store(obj) as! NSNumber
//            writer(num.description)
        default:
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [NSDebugDescriptionErrorKey : "Invalid object cannot be serialized"])
        }
    }

    func serializeString(_ str: String) throws {
        writer("\"")
        for scalar in str.unicodeScalars {
            switch scalar {
                case "\"":
                    writer("\\\"") // U+0022 quotation mark
                case "\\":
                    writer("\\\\") // U+005C reverse solidus
                case "/":
                    if !withoutEscapingSlashes { writer("\\") }
                    writer("/") // U+002F solidus
                case "\u{8}":
                    writer("\\b") // U+0008 backspace
                case "\u{c}":
                    writer("\\f") // U+000C form feed
                case "\n":
                    writer("\\n") // U+000A line feed
                case "\r":
                    writer("\\r") // U+000D carriage return
                case "\t":
                    writer("\\t") // U+0009 tab
                case "\u{0}"..."\u{f}":
                    writer("\\u000\(String(scalar.value, radix: 16))") // U+0000 to U+000F
                case "\u{10}"..."\u{1f}":
                    writer("\\u00\(String(scalar.value, radix: 16))") // U+0010 to U+001F
                default:
                    writer(String(scalar))
            }
        }
        writer("\"")
    }

    private func serializeFloat<T: FloatingPoint & LosslessStringConvertible>(_ num: T) throws {
        guard num.isFinite else {
             throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [NSDebugDescriptionErrorKey : "Invalid number value (\(num)) in JSON write"])
        }
        var str = num.description
        if str.hasSuffix(".0") {
            str.removeLast(2)
        }
        writer(str)
    }

//    mutating func serializeNumber(_ num: NSNumber) throws {
//        if CFNumberIsFloatType(num._cfObject) {
//            try serializeFloat(num.doubleValue)
//        } else {
//            switch num._cfTypeID {
//            case CFBooleanGetTypeID():
//                writer(num.boolValue.description)
//            default:
//                writer(num.stringValue)
//            }
//        }
//    }

    mutating func serializeArray(_ array: [Any?]) throws {
        writer("[")
        if pretty {
            writer("\n")
            incIndent()
        }

        var first = true
        for elem in array {
            if first {
                first = false
            } else if pretty {
                writer(",\n")
            } else {
                writer(",")
            }
            if pretty {
                writeIndent()
            }
            try serializeJSON(elem)
        }
        if pretty {
            writer("\n")
            decAndWriteIndent()
        }
        writer("]")
    }

    mutating func serializeDictionary(_ dict: Dictionary<AnyHashable, Any?>) throws {
        writer("{")
        if pretty {
            writer("\n")
            incIndent()
            if dict.count > 0 {
                writeIndent()
            }
        }

        var first = true

        func serializeDictionaryElement(key: AnyHashable, value: Any?) throws {
            if first {
                first = false
            } else if pretty {
                writer(",\n")
                writeIndent()
            } else {
                writer(",")
            }

            if let key = key as? String {
                try serializeString(key)
            } else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [NSDebugDescriptionErrorKey : "NSDictionary key must be NSString"])
            }
            pretty ? writer(" : ") : writer(":")
            try serializeJSON(value)
        }

        if sortedKeys {
            let elems = try dict.sorted(by: { a, b in
                guard let a = a.key as? String,
                    let b = b.key as? String else {
                        throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [NSDebugDescriptionErrorKey : "NSDictionary key must be NSString"])
                }
                let options: NSString.CompareOptions = [.numeric, .caseInsensitive, .forcedOrdering]
                let range: Range<String.Index>  = a.startIndex..<a.endIndex
                let locale = NSLocale.system

                return a.compare(b, options: options, range: range, locale: locale) == .orderedAscending
            })
            for elem in elems {
                try serializeDictionaryElement(key: elem.key, value: elem.value)
            }
        } else {
            for (key, value) in dict {
                try serializeDictionaryElement(key: key, value: value)
            }
        }

        if pretty {
            writer("\n")
            decAndWriteIndent()
        }
        writer("}")
    }

    func serializeNull() throws {
        writer("null")
    }

    let indentAmount = 2

    mutating func incIndent() {
        indent += indentAmount
    }

    mutating func incAndWriteIndent() {
        indent += indentAmount
        writeIndent()
    }

    mutating func decAndWriteIndent() {
        indent -= indentAmount
        writeIndent()
    }

    func writeIndent() {
        for _ in 0..<indent {
            writer(" ")
        }
    }

}

enum JSONValue: Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue {
    var isValue: Bool {
        switch self {
        case .array, .object:
            return false
        case .null, .number, .string, .bool:
            return true
        }
    }

    var isContainer: Bool {
        switch self {
        case .array, .object:
            return true
        case .null, .number, .string, .bool:
            return false
        }
    }
}

extension JSONValue {
    var debugDataTypeDescription: String {
        switch self {
        case .array:
            return "an array"
        case .bool:
            return "bool"
        case .number:
            return "a number"
        case .string:
            return "a string"
        case .object:
            return "a dictionary"
        case .null:
            return "null"
        }
    }
}

extension NSNumber {
    static func fromJSONNumber(_ string: String) -> NSNumber? {
        let decIndex = string.firstIndex(of: ".")
        let expIndex = string.firstIndex(of: "e")
        let isInteger = decIndex == nil && expIndex == nil
        let isNegative = string.utf8[string.utf8.startIndex] == UInt8(ascii: "-")
        let digitCount = string[string.startIndex..<(expIndex ?? string.endIndex)].count

        // Try Int64() or UInt64() first
        if isInteger {
            if isNegative {
                if digitCount <= 19, let intValue = Int64(string) {
                    return NSNumber(value: intValue)
                }
            } else {
                if digitCount <= 20, let uintValue = UInt64(string) {
                    return NSNumber(value: uintValue)
                }
            }
        }

        var exp = 0

        if let expIndex = expIndex {
            let expStartIndex = string.index(after: expIndex)
            if let parsed = Int(string[expStartIndex...]) {
                exp = parsed
            }
        }

        // Decimal holds more digits of precision but a smaller exponent than Double
        // so try that if the exponent fits and there are more digits than Double can hold
        if digitCount > 17, exp >= -128, exp <= 127, let decimal = Decimal(string: string), decimal.isFinite {
            return NSDecimalNumber(decimal: decimal)
        }

        // Fall back to Double() for everything else
        if let doubleValue = Double(string), doubleValue.isFinite {
            return NSNumber(value: doubleValue)
        }

        return nil
    }
}
