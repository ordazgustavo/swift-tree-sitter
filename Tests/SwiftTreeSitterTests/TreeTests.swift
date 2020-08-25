import XCTest
@testable import TreeSitter
@testable import SwiftTreeSitter

final class TreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    func testTreeEdit() {
        let language = JavaScript()
        let parser = Parser()
        parser.setLanguage(language.parser)
        
        let tree = parser.parse(source: "  abc  !==  def")!
        
        XCTAssertEqual(
            tree.rootNode().toSexp(),
            "(program (expression_statement (binary_expression left: (identifier) right: (identifier))))"
        );
        
        // edit entirely within the tree's padding:
        // resize the padding of the tree and its leftmost descendants.
        _ = {
            let tree2 = tree.clone();
            var inputEdit = InputEdit(
                startByte: 1,
                oldEndByte: 1,
                newEndByte: 2,
                startPoint: Point(row: 0, column: 1),
                oldEndPoint: Point(row: 0, column: 1),
                newEndPoint: Point(row: 0, column: 2)
            )
            tree2.edit(&inputEdit)
            let expr = tree2.rootNode().child(at: 0)!.child(at: 0)!
            let child1 = expr.child(at: 0)!
            let child2 = expr.child(at: 1)!
            
            XCTAssertTrue(expr.hasChanges())
            XCTAssertEqual(expr.startByte, 3)
            XCTAssertEqual(expr.endByte, 16)
            XCTAssertTrue(child1.hasChanges())
            XCTAssertEqual(child1.startByte, 3)
            XCTAssertEqual(child1.endByte, 6)
            XCTAssertTrue(!child2.hasChanges())
            XCTAssertEqual(child2.startByte, 8)
            XCTAssertEqual(child2.endByte, 11)
        }()
        
        // edit starting in the tree's padding but extending into its content:
        // shrink the content to compenstate for the expanded padding.
        _ = {
            let tree2 = tree.clone();
            var inputEdit = InputEdit(
                startByte: 1,
                oldEndByte: 4,
                newEndByte: 5,
                startPoint: Point(row: 0, column: 1),
                oldEndPoint: Point(row: 0, column: 5),
                newEndPoint: Point(row: 0, column: 5)
            )
            tree2.edit(&inputEdit)
            let expr = tree2.rootNode().child(at: 0)!.child(at: 0)!
            let child1 = expr.child(at: 0)!
            let child2 = expr.child(at: 1)!

            XCTAssertTrue(expr.hasChanges())
            XCTAssertEqual(expr.startByte, 5)
            XCTAssertEqual(expr.endByte, 16)
            XCTAssertTrue(child1.hasChanges())
            XCTAssertEqual(child1.startByte, 5)
            XCTAssertEqual(child1.endByte, 6)
            XCTAssertTrue(!child2.hasChanges())
            XCTAssertEqual(child2.startByte, 8)
            XCTAssertEqual(child2.endByte, 11)
        }()
        
        // insertion at the edge of a tree's padding:
        // expand the tree's padding.
        _ = {
            let tree2 = tree.clone();
            var inputEdit = InputEdit(
                startByte: 2,
                oldEndByte: 2,
                newEndByte: 4,
                startPoint: Point(row: 0, column: 2),
                oldEndPoint: Point(row: 0, column: 2),
                newEndPoint: Point(row: 0, column: 4)
            )
            tree2.edit(&inputEdit)
            let expr = tree2.rootNode().child(at: 0)!.child(at: 0)!
            let child1 = expr.child(at: 0)!
            let child2 = expr.child(at: 1)!

            XCTAssertTrue(expr.hasChanges())
            XCTAssertEqual(expr.startByte, 4)
            XCTAssertEqual(expr.endByte, 17)
            XCTAssertTrue(child1.hasChanges())
            XCTAssertEqual(child1.startByte, 4)
            XCTAssertEqual(child1.endByte, 7)
            XCTAssertTrue(!child2.hasChanges())
            XCTAssertEqual(child2.startByte, 9)
            XCTAssertEqual(child2.endByte, 12)
        }()
        
        // replacement starting at the edge of the tree's padding:
        // resize the content and not the padding.
        _ = {
            let tree2 = tree.clone();
            var inputEdit = InputEdit(
                startByte: 2,
                oldEndByte: 2,
                newEndByte: 4,
                startPoint: Point(row: 0, column: 2),
                oldEndPoint: Point(row: 0, column: 2),
                newEndPoint: Point(row: 0, column: 4)
            )
            tree2.edit(&inputEdit)
            let expr = tree2.rootNode().child(at: 0)!.child(at: 0)!
            let child1 = expr.child(at: 0)!
            let child2 = expr.child(at: 1)!

            XCTAssertTrue(expr.hasChanges())
            XCTAssertEqual(expr.startByte, 4)
            XCTAssertEqual(expr.endByte, 17)
            XCTAssertTrue(child1.hasChanges())
            XCTAssertEqual(child1.startByte, 4)
            XCTAssertEqual(child1.endByte, 7)
            XCTAssertTrue(!child2.hasChanges())
            XCTAssertEqual(child2.startByte, 9)
            XCTAssertEqual(child2.endByte, 12)
        }()
        
        // deletion that spans more than one child node:
        // shrink subsequent child nodes.
        _ = {
            let tree2 = tree.clone();
            var inputEdit = InputEdit(
                startByte: 1,
                oldEndByte: 11,
                newEndByte: 4,
                startPoint: Point(row: 0, column: 1),
                oldEndPoint: Point(row: 0, column: 11),
                newEndPoint: Point(row: 0, column: 4)
            )
            tree2.edit(&inputEdit)
            let expr = tree2.rootNode().child(at: 0)!.child(at: 0)!
            let child1 = expr.child(at: 0)!
            let child2 = expr.child(at: 1)!
            let child3 = expr.child(at: 2)!

            XCTAssertTrue(expr.hasChanges())
            XCTAssertEqual(expr.startByte, 4)
            XCTAssertEqual(expr.endByte, 8)
            XCTAssertTrue(child1.hasChanges())
            XCTAssertEqual(child1.startByte, 4)
            XCTAssertEqual(child1.endByte, 4)
            XCTAssertTrue(child2.hasChanges())
            XCTAssertEqual(child2.startByte, 4)
            XCTAssertEqual(child2.endByte, 4)
            XCTAssertTrue(child3.hasChanges())
            XCTAssertEqual(child3.startByte, 5)
            XCTAssertEqual(child3.endByte, 8)
        }()
        
        // insertion at the end of the tree:
        // extend the tree's content.
        _ = {
            let tree2 = tree.clone();
            var inputEdit = InputEdit(
                startByte: 15,
                oldEndByte: 15,
                newEndByte: 16,
                startPoint: Point(row: 0, column: 15),
                oldEndPoint: Point(row: 0, column: 15),
                newEndPoint: Point(row: 0, column: 16)
            )
            tree2.edit(&inputEdit)
            let expr = tree2.rootNode().child(at: 0)!.child(at: 0)!
            let child1 = expr.child(at: 0)!
            let child2 = expr.child(at: 1)!
            let child3 = expr.child(at: 2)!

            XCTAssertTrue(expr.hasChanges())
            XCTAssertEqual(expr.startByte, 2)
            XCTAssertEqual(expr.endByte, 16)
            XCTAssertTrue(!child1.hasChanges())
            XCTAssertEqual(child1.endByte, 5)
            XCTAssertTrue(!child2.hasChanges())
            XCTAssertEqual(child2.endByte, 10)
            XCTAssertTrue(child3.hasChanges())
            XCTAssertEqual(child3.endByte, 16)
        }()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    static var allTests = [
        ("testTreeEdit", testTreeEdit)
    ]
}
