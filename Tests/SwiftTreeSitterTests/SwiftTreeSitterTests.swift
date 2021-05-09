import XCTest

@testable import TreeSitter
@testable import SwiftTreeSitter

final class SwiftTreeSitterTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    func testPointComparableImplementation() {
        let startPoint1 = Point(row: CUnsignedInt(1), column: CUnsignedInt(1))
        let endPoint1 = Point(row: CUnsignedInt(1), column: CUnsignedInt(1))
        XCTAssertEqual(startPoint1, endPoint1)
        
        let startPoint2 = Point(row: CUnsignedInt(1), column: CUnsignedInt(1))
        let endPoint2 = Point(row: CUnsignedInt(1), column: CUnsignedInt(2))
        XCTAssertLessThan(startPoint2, endPoint2)
        
        let startPoint3 = Point(row: CUnsignedInt(1), column: CUnsignedInt(1))
        let endPoint3 = Point(row: CUnsignedInt(2), column: CUnsignedInt(1))
        XCTAssertLessThan(startPoint3, endPoint3)
        
        let startPoint4 = Point(row: CUnsignedInt(2), column: CUnsignedInt(1))
        let endPoint4 = Point(row: CUnsignedInt(1), column: CUnsignedInt(2))
        XCTAssertGreaterThan(startPoint4, endPoint4)
    }
    
    func testStsRangeComparableImplementation() {
        let s1 = STSRange(
            startPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            endPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            startByte: 1,
            endByte: 1
        )
        let e1 = STSRange(
            startPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            endPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            startByte: 1,
            endByte: 1
        )
        XCTAssertEqual(s1, e1)
        
        let s2 = STSRange(
            startPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            endPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            startByte: 1,
            endByte: 1
        )
        let e2 = STSRange(
            startPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(1)),
            endPoint: Point(row: CUnsignedInt(1), column: CUnsignedInt(2)),
            startByte: 1,
            endByte: 2
        )
        XCTAssertLessThan(s2, e2)
    }
    
    override func tearDown() {
        super.tearDown()
    }

    static var allTests = [
        ("testPointComparableImplementation", testPointComparableImplementation),
        ("testStsRangeComparableImplementation", testStsRangeComparableImplementation),
    ]
}
