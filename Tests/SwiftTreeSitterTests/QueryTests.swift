import XCTest
@testable import TreeSitter
@testable import SwiftTreeSitter

final class QueryTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    func testQueryErrorsOnInvalidSyntax() {
        let language = JavaScript()
        let q1 = try? Query(language: language.parser, source: "(if_statement)").build().get()
        let q2 = try? Query(language: language.parser, source: "(if_statement condition:(identifier))").build().get()
        XCTAssertTrue(q1 != nil)
        XCTAssertTrue(q2 != nil)
        
        // Mismatched parens
        assert(
            Query(language: language.parser, source: "(if_statement").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "(if_statement",
                    "             ^",
                ].joined(separator: "\n")
            )
        )
        assert(
            Query(language: language.parser, source: "(if_statement))").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "(if_statement))",
                    "              ^",
                ].joined(separator: "\n")
            )
        )
        
        // Return an error at the *beginning* of a bare identifier not followed a colon.
        // If there's a colon but no pattern, return an error at the end of the colon.
        assert(
            Query(language: language.parser, source: "(if_statement identifier)").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "(if_statement identifier)",
                    "              ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            Query(language: language.parser, source: "(if_statement condition:)").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "(if_statement condition:)",
                    "                        ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            Query(language: language.parser, source: #"(identifier) "h "#).build(),
            containsError: QueryError.syntax(
                1,
                [
                    #"(identifier) "h "#,
                    #"             ^"#,
                ].joined(separator: "\n")
            )
        )
        
        assert(
            Query(language: language.parser, source: "((identifier) [])").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "((identifier) [])",
                    "               ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            Query(language: language.parser, source: "((identifier) (#a)").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "((identifier) (#a)",
                    "                  ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            Query(language: language.parser, source: "((identifier) @x (#eq? @x a").build(),
            containsError: QueryError.syntax(
                1,
                [
                    "((identifier) @x (#eq? @x a",
                    "                           ^",
                ].joined(separator: "\n")
            )
        )
    }

    
    func testQueryMatchesWithNamedWildcard() {
        let lang = JavaScript()
        let query = Query(
            language: lang.parser,
            source: """
            (return_statement (_) @the-return-value)
            (binary_expression operator: _ @the-operator)
            """
        )
        let _ = query.build()
        
        let source = "return a + b - c;"
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let matches = cursor.matches(query: query, for: tree.rootNode()) {
            $0.utf16Text(source: source)
        }
        
        XCTAssertEqual(
            collectMatches(matches: matches, query: query, source: source),
            [
                [0: ["the-return-value", "a + b - c"]],
                [1: ["the-operator", "+"]],
                [1: ["the-operator", "-"]]
            ]
        )
    }
    
    func testQueryCapturesWithTextConditions() {
        let lang = JavaScript()
        let query = Query(
            language: lang.parser,
            source: """
            ((identifier) @constant
             (#match? @constant "^[A-Z]{2,}$"))

             ((identifier) @constructor
              (#match? @constructor "^[A-Z]"))

            ((identifier) @function.builtin
             (#eq? @function.builtin "require"))

            ((identifier) @variable
             (#not-match? @variable "^(lambda|load)$"))
            """
        )
        let _ = query.build()
        
        let source = """
        toad
        load
        panda
        lambda
        const ab = require('./ab');
        new Cd(EF);
        """
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let captures = cursor.captures(query: query, for: tree.rootNode()) {
            $0.utf16Text(source: source)
        }
        
        XCTAssertEqual(
            collectCaptures(captures: captures, query: query, source: source),
            [
                ["variable", "toad"],
                ["variable", "panda"],
                ["variable", "ab"],
                ["function.builtin", "require"],
                ["variable", "require"],
                ["constructor", "Cd"],
                ["variable", "Cd"],
                ["constant", "EF"],
                ["constructor", "EF"],
                ["variable", "EF"],
            ]
        )
    }
    
    override func tearDown() {
        super.tearDown()
    }

    static var allTests = [
        ("testQueryErrorsOnInvalidSyntax", testQueryErrorsOnInvalidSyntax),
        ("testQueryMatchesWithNamedWildcard", testQueryMatchesWithNamedWildcard),
        ("testQueryCapturesWithTextConditions", testQueryCapturesWithTextConditions),
    ]
    
    func collectMatches(
        matches: QueryMatches,
        query: Query,
        source: String
    ) -> [[Int: [String]]] {
        matches.map { match in
            [
                match.patternIndex: formatCaptures(
                    captures: match.captures,
                    query: query,
                    source: source
                ).reduce([], +)
            ]
        }
    }
    
    func collectCaptures(
        captures: QueryCaptures,
        query: Query,
        source: String
    ) -> [[String]] {
        formatCaptures(
            captures: captures.map { $0.captures[$1] },
            query: query,
            source: source
        )
    }
    
    func formatCaptures(
        captures: [QueryCapture],
        query: Query,
        source: String
    ) -> [[String]] {
        captures.map { capture in
            [
                query.captureNames[Int(capture.index)],
                capture.node.utf8Text(source: source)
            ]
        }
    }
}

extension XCTestCase {
    func assert<T, E: Error & Equatable>(
        _ result: Result<T, E>?,
        containsError expectedError: E,
        in file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success?:
            XCTFail("No error thrown", file: file, line: line)
        case .failure(let error)?:
            XCTAssertEqual(
                error,
                expectedError,
                file: file, line: line
            )
        case nil:
            XCTFail("Result was nil", file: file, line: line)
        }
    }
}
