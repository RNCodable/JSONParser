//
//  TestJSONParser.swift
//  
//
//  Created by Rob Napier on 9/10/22.
//

import XCTest
import JSONParser
import JSONValue

// Things not tested in stdlib
final class TestJSONParser: XCTestCase {
    func testTrailingContentThrows() throws {
        let json = Data(#"""
        [1,2,3]
        123
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTrailingCommaInArray() throws {
        let json = Data(#"""
        [1,2,3,]
        """#.utf8)

        XCTAssertEqual(try RNJSONDecoder().decode(JSONValue.self, from: json), [1,2,3])
    }

    func testUnexpectedCharacterInArrayThrows() {
        let json = Data(#"""
        [1,2,3 x]
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testUnexpectedCharacterBeforeColonThrows() {
        let json = Data(#"""
        { "x" x : y }
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTrailingCommaInObject() throws {
        let json = Data(#"""
        { "x": "y", }
        """#.utf8)

        XCTAssertEqual(try RNJSONDecoder().decode(JSONValue.self, from: json), ["x": "y"])
    }

    func testUnexpectedCharacterBeforeCloseBraceThrows() {
        let json = Data(#"""
        { "x" : "y" z }
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTruncatedTrueThrows() {
        let json = Data(#"""
        tru
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testMisspelledTrueThrows() {
        let json = Data(#"""
        truth
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTruncatedFalseThrows() {
        let json = Data(#"""
        fal
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testMisspelledFalseThrows() {
        let json = Data(#"""
        flase
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTruncatedNullThrows() {
        let json = Data(#"""
        nul
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testMisspelledNullThrows() {
        let json = Data(#"""
        nuii
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testUnquotedKeyThrows() {
        let json = Data(#"""
        { x: "y" }
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testUnescapedControlThrows() {
        let json = Data("""
        "\u{08}"
        """.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testInvalidEscapeThrows() {
        let json = Data(#"""
        "\x"
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testValidSurrogateIsDecoded() {
        // G-Clef
        let json = Data(#"""
        "\uD834\uDD1E"
        """#.utf8)

        XCTAssertEqual(try RNJSONDecoder().decode(JSONValue.self, from: json), "\u{1D11E}")
    }


    func testMissingLowSurrogateThrows() {
        // G-Clef high surrogate only
        let json = Data(#"""
        "\uD834abc"
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testInvalidLowSurrogateThrows() {
        // G-Clef high surrogate, escaped non-surrogate
        let json = Data(#"""
        "\uD834\u000a"
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testInvalidSurrogateOrderThrows() {
        // Backwards G-Clef
        let json = Data(#"""
        "\uDD1E\uD834"
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testHighSurrogateOnlyThrows() {
        // G-Clef high surrogate followed by eof
        let json = Data(#"""
        "\uD834
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTruncatedEscapeThrows() {
        let json = Data(#"""
        "\
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTruncatedUnicodeEscapeThrows() {
        let json = Data(#"""
        "\u12
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testInvalidUnicodeHexThrows() {
        let json = Data(#"""
        "\u12xx"
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testEscapeSequencesTranslate() {
        let json = Data(#"""
        "\"\\\/\b\f\n\r\t\u000a"
        """#.utf8)

        XCTAssertEqual(try RNJSONDecoder().decode(JSONValue.self, from: json), "\"\\/\u{08}\u{0c}\n\r\t\n")
    }

    func testLeadingZeroThrows() {
        let json = Data(#"""
        0123
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testUnexpectedExponentThrows() {
        let json = Data(#"""
        -e12
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testUnexpectedNegativeThrows() {
        let json = Data(#"""
        1-1
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testMissingExponentThrows() {
        let json = Data(#"""
        [1e]
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testInvalidDigitThrows() {
        let json = Data(#"""
        [1x]
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

    func testTruncatedExponentThrows() {
        let json = Data(#"""
        1e
        """#.utf8)

        XCTAssertThrowsError(try RNJSONDecoder().decode(JSONValue.self, from: json))
    }

}
