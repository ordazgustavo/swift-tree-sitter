import XCTest
@testable import TreeSitter
@testable import SwiftTreeSitter
@testable import TreeSitterJSON

final class SwiftTreeSitterTests: XCTestCase {
    let parser = Parser()
    let language = Language(tree_sitter_json())
    
    override func setUp() {
        super.setUp()
        
        self.parser.setLanguage(self.language)
    }
    
    func testParsesString() {
        let sourceCode = "[1, null]"

        let tree = self.parser.parseString(source: sourceCode)!
        let rootNode = tree.rootNode()
        
        let arrayNode = rootNode.namedChild(at: 0)
        let numberNode = arrayNode!.namedChild(at: 0)

        XCTAssertEqual(rootNode.kind(), "document")
        XCTAssertEqual(arrayNode!.kind(), "array")
        XCTAssertEqual(numberNode!.kind(), "number")
        
        addTeardownBlock {
            self.parser.reset()
        }
    }
    
    func testParsesUTF8String() {
        let sourceCode = "{\"value\": [1, null]}"

        let tree = self.parser.parseString(source: sourceCode)!
        let rootNode = tree.rootNode()

        XCTAssertEqual(rootNode.kind(), "document")
        XCTAssertEqual(rootNode.startPosition().column, UInt32(0))
        XCTAssertEqual(rootNode.endPosition().column, UInt32(20))
        
        addTeardownBlock {
            self.parser.reset()
        }
    }
    
    func testParsesUTF8StringSlices() {
        let sourceCode = "{\"value\": [1, null]}"

        let tree = self.parser.parse(text: sourceCode, oldTree: nil)!
        let rootNode = tree.rootNode()

        XCTAssertEqual(rootNode.kind(), "document")
        XCTAssertEqual(rootNode.startPosition().column, UInt32(0))
        XCTAssertEqual(rootNode.endPosition().column, UInt32(21))
        
        addTeardownBlock {
            self.parser.reset()
        }
    }
    
    override func tearDown() {
        super.tearDown()
    }

    static var allTests = [
        ("testParsesString", testParsesString),
        ("testParsesUTF8String", testParsesUTF8String),
        ("testParsesUTF8StringSlices", testParsesUTF8StringSlices),
    ]
}
