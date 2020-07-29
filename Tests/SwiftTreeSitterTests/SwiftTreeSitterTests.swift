import XCTest
@testable import TreeSitter
@testable import SwiftTreeSitter
@testable import TreeSitterJSON

final class SwiftTreeSitterTests: XCTestCase {
    let languageJson = Language(tree_sitter_json())
    
    override func setUp() {
        super.setUp()
    }
    
    func testParsesString() {
        let parser = Parser()
        let sourceCode = "[1, null]"
        parser.setLanguage(languageJson)
        let tree = parser.parseString(source: sourceCode, oldTree: nil)!
        let rootNode = tree.rootNode()
        
        let arrayNode = rootNode.namedChild(at: 0)
        let numberNode = arrayNode!.namedChild(at: 0)

        XCTAssertEqual(rootNode.kind(), "document")
        XCTAssertEqual(arrayNode!.kind(), "array")
        XCTAssertEqual(numberNode!.kind(), "number")
    }
    
    func testParsesUTF8String() {
        let parser = Parser()
        let sourceCode = "{\"value\": [1, null]}"
        parser.setLanguage(languageJson)
        let tree = parser.parseString(source: sourceCode, oldTree: nil)!
        let rootNode = tree.rootNode()

        XCTAssertEqual(rootNode.kind(), "document")
        XCTAssertEqual(rootNode.startPosition().column, UInt32(0))
        XCTAssertEqual(rootNode.endPosition().column, UInt32(20))
        
    }
    
    override func tearDown() {
        super.tearDown()
    }

    static var allTests = [
        ("testParsesString", testParsesString),
        ("testParsesUTF8String", testParsesUTF8String),
    ]
}
