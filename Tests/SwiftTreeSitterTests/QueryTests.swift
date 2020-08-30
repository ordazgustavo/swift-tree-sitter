import XCTest
@testable import TreeSitter
@testable import SwiftTreeSitter

final class QueryTests: XCTestCase {
    func testQueryErrorsOnInvalidSyntax() {
        let language = JavaScript()
        let q1 = try? Query(language: language.parser, source: "(if_statement)")
        let q2 = try? Query(
            language: language.parser,
            source: "(if_statement condition:(identifier))"
        )
        XCTAssertTrue(q1 != nil)
        XCTAssertTrue(q2 != nil)
        
        // Mismatched parens
        assert(
            try Query(language: language.parser, source: "(if_statement"),
            throws: QueryError.syntax(
                1,
                [
                    "(if_statement",
                    "             ^",
                ].joined(separator: "\n")
            )
        )
        assert(
            try Query(language: language.parser, source: "(if_statement))"),
            throws: QueryError.syntax(
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
            try Query(language: language.parser, source: "(if_statement identifier)"),
            throws: QueryError.syntax(
                1,
                [
                    "(if_statement identifier)",
                    "              ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            try Query(language: language.parser, source: "(if_statement condition:)"),
            throws: QueryError.syntax(
                1,
                [
                    "(if_statement condition:)",
                    "                        ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            try Query(language: language.parser, source: #"(identifier) "h "#),
            throws: QueryError.syntax(
                1,
                [
                    #"(identifier) "h "#,
                    #"             ^"#,
                ].joined(separator: "\n")
            )
        )
        
        assert(
            try Query(language: language.parser, source: "((identifier) [])"),
            throws: QueryError.syntax(
                1,
                [
                    "((identifier) [])",
                    "               ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            try Query(language: language.parser, source: "((identifier) (#a)"),
            throws: QueryError.syntax(
                1,
                [
                    "((identifier) (#a)",
                    "                  ^",
                ].joined(separator: "\n")
            )
        )
        
        assert(
            try Query(language: language.parser, source: "((identifier) @x (#eq? @x a"),
            throws: QueryError.syntax(
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
        let query = try! Query(
            language: lang.parser,
            source: """
            (return_statement (_) @the-return-value)
            (binary_expression operator: _ @the-operator)
            """
        )
        
        let source = "return a + b - c;"
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let matches = cursor.matches(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
        XCTAssertEqual(
            collectMatches(matches: matches, query: query, source: source),
            [
                [0: [["the-return-value", "a + b - c"]]],
                [1: [["the-operator", "+"]]],
                [1: [["the-operator", "-"]]]
            ]
        )
    }
    
    func testQueryCapturesWithTextConditions() {
        let lang = JavaScript()
        let query = try! Query(
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
        
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
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
    
    func testQueryCapturesBasic() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            (pair
              key: _ @method.def
              (function
                name: (identifier) @method.alias))
            (variable_declarator
              name: _ @function.def
              value: (function
                name: (identifier) @function.alias))
            ":" @delimiter
            "=" @operator
            """
        )
        
        let source = """
        a({
            bc: function de() {
            const fg = function hi() {}
            },
            jk: function lm() {
            const no = function pq() {}
            },
        });
        """
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let matches = cursor.matches(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )

        XCTAssertEqual(
            collectMatches(matches: matches, query: query, source: source),
            [
                [2: [["delimiter", ":"]]],
                [0: [["method.def", "bc"], ["method.alias", "de"]]],
                [3: [["operator", "="]]],
                [1: [["function.def", "fg"], ["function.alias", "hi"]]],
                [2: [["delimiter", ":"]]],
                [0: [["method.def", "jk"], ["method.alias", "lm"]]],
                [3: [["operator", "="]]],
                [1: [["function.def", "no"], ["function.alias", "pq"]]],
            ]
        )
        
        let captures = cursor.captures(query: query, for: tree.rootNode) {
            $0.utf8Text(source: source)
        }
        XCTAssertEqual(
            collectCaptures(captures: captures, query: query, source: source),
            [
                ["method.def", "bc"],
                ["delimiter", ":"],
                ["method.alias", "de"],
                ["function.def", "fg"],
                ["operator", "="],
                ["function.alias", "hi"],
                ["method.def", "jk"],
                ["delimiter", ":"],
                ["method.alias", "lm"],
                ["function.def", "no"],
                ["operator", "="],
                ["function.alias", "pq"],
            ]
        )
    }
    
    func testQueryCapturesWithDuplicates() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            (variable_declarator
                name: (identifier) @function
                value: (function))
            (identifier) @variable
            """
        )
        
        let source = """
        var x = function() {};
        """
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
        XCTAssertEqual(
            collectCaptures(captures: captures, query: query, source: source),
            [
                ["function", "x"],
                ["variable", "x"],
            ]
        )
    }
    
    func testQueryCapturesWithManyNestedResultsWithoutFields() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            (pair
              key: _ @method-def
              (arrow_function))
            ":" @colon
            "," @comma
            """
        )
        
        let methodCount = 50
        var source = "x = { y: {\n"
        for i in 0..<methodCount {
            source += "    method\(i): $ => null,"
        }
        source += "}};\n"
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
        XCTAssertEqual(
            collectCaptures(
                captures: captures,
                query: query,
                source: source
            )[0..<13],
            [
                ["colon", ":"],
                ["method-def", "method0"],
                ["colon", ":"],
                ["comma", ","],
                ["method-def", "method1"],
                ["colon", ":"],
                ["comma", ","],
                ["method-def", "method2"],
                ["colon", ":"],
                ["comma", ","],
                ["method-def", "method3"],
                ["colon", ":"],
                ["comma", ","],
            ]
        )
    }
    
    func testQueryCapturesWithManyNestedResultsWithFields() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            ((ternary_expression
                condition: (identifier) @left
                consequence: (member_expression
                    object: (identifier) @right)
                alternative: (null))
             (#eq? @left @right))
            """
        )
        
        let count = 50
        var source = "a ? {"
        for i in 0..<count {
            source += "  x: y\(i) ? y\(i).z : null,"
        }
        source += "} : null;\n"
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
        XCTAssertEqual(
            collectCaptures(
                captures: captures,
                query: query,
                source: source
            )[0..<20],
            [
                ["left", "y0"],
                ["right", "y0"],
                ["left", "y1"],
                ["right", "y1"],
                ["left", "y2"],
                ["right", "y2"],
                ["left", "y3"],
                ["right", "y3"],
                ["left", "y4"],
                ["right", "y4"],
                ["left", "y5"],
                ["right", "y5"],
                ["left", "y6"],
                ["right", "y6"],
                ["left", "y7"],
                ["right", "y7"],
                ["left", "y8"],
                ["right", "y8"],
                ["left", "y9"],
                ["right", "y9"],
            ]
        )
    }
    
    func testQueryCapturesWithTooManyNestedResults() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            ;; easy 👇
            (call_expression
              function: (member_expression
                property: (property_identifier) @method-name))

            ;; hard 👇
            (call_expression
              function: (member_expression
                property: (property_identifier) @template-tag)
              arguments: (template_string)) @template-call

            """
        )

        let source = """
        a(b => {
            b.c0().d0 `😄`;
            b.c1().d1 `😄`;
            b.c2().d2 `😄`;
            b.c3().d3 `😄`;
            b.c4().d4 `😄`;
            b.c5().d5 `😄`;
            b.c6().d6 `😄`;
            b.c7().d7 `😄`;
            b.c8().d8 `😄`;
            b.c9().d9 `😄`;
        }).e().f ``;
        """.trimmingCharacters(in: .whitespaces)

        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()

        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        let result = collectCaptures(
            captures: captures,
            query: query,
            source: source
        )

        XCTAssertEqual(
            result[0..<4],
            [
                ["template-call", "b.c0().d0 `😄`"],
                ["method-name", "c0"],
                ["method-name", "d0"],
                ["template-tag", "d0"],
            ]
        )

        XCTAssertEqual(
            result[36..<40],
            [
                ["template-call", "b.c9().d9 `😄`"],
                ["method-name", "c9"],
                ["method-name", "d9"],
                ["template-tag", "d9"],
            ]
        )
        
        XCTAssertEqual(
            result[40...],
            [
                ["method-name", "e"],
                ["method-name", "f"],
            ]
        )
    }
    
    func testQueryCapturesOrderedByBothStartAndEndPositions() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            (call_expression) @call
            (member_expression) @member
            (identifier) @variable
            """
        )
        
        let source = """
        a.b(c.d().e).f;
        """
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
        XCTAssertEqual(
            collectCaptures(captures: captures, query: query, source: source),
            [
                ["member", "a.b(c.d().e).f"],
                ["call", "a.b(c.d().e)"],
                ["member", "a.b"],
                ["variable", "a"],
                ["member", "c.d().e"],
                ["call", "c.d()"],
                ["member", "c.d"],
                ["variable", "c"],
            ]
        )
    }
    
    func testQueryCapturesWithMatchesRemoved() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            (binary_expression
                left: (identifier) @left
                operator: _ @op
                right: (identifier) @right)
            """
        )
        
        let source = """
        a === b && c > d && e < f;
        """
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        
        var capturedStrings = [String]()
        for (m, i) in captures {
            let capture = m.captures[i]
            let text = capture.node.utf8Text(source: source)
            if text == "a" {
                m.remove()
                continue
            }
            capturedStrings.append(text)
        }
        
        XCTAssertEqual(capturedStrings, ["c", ">", "d", "e", "<", "f"])
    }
    
    func testQueryCapturesAndMatchesIteratorsAreFused() {
        let lang = JavaScript()
        let query = try! Query(
            language: lang.parser,
            source: """
            (comment) @comment
            """
        )
        
        let source = """
        // one
        // two
        // three
        /* unfinished
        """
        
        let parser = Parser()
        parser.setLanguage(lang.parser)
        let tree = parser.parse(source: source)!
        let cursor = QueryCursor()
        
        let captures = cursor.captures(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        .makeIterator()
        
        XCTAssertEqual(captures.next()!.0.captures[0].index, 0)
        XCTAssertEqual(captures.next()!.0.captures[0].index, 0)
        XCTAssertEqual(captures.next()!.0.captures[0].index, 0)
        XCTAssert(captures.next() == nil)
        XCTAssert(captures.next() == nil)
        XCTAssert(captures.next() == nil)
        
        let matches = cursor.matches(
            query: query,
            for: tree.rootNode,
            textCallback: toCallback(source)
        )
        .makeIterator()
        
        XCTAssertEqual(matches.next()!.captures[0].index, 0)
        XCTAssertEqual(matches.next()!.captures[0].index, 0)
        XCTAssertEqual(matches.next()!.captures[0].index, 0)
        XCTAssert(matches.next() == nil)
        XCTAssert(matches.next() == nil)
        XCTAssert(matches.next() == nil)
    }
    
    func testQueryStartByteForPattern() {
        let lang = JavaScript()
        let patterns1 = """
            "+" @operator
            "-" @operator
            "*" @operator
            "=" @operator
            "=>" @operator
        """.trimmingCharacters(in: .whitespaces)
        
        let patterns2 = """
            (identifier) @a
            (string) @b
        """.trimmingCharacters(in: .whitespaces)
        
        let patterns3 = """
            ((identifier) @b (#match? @b i))
            (function_declaration name: (identifier) @c)
            (method_definition name: (identifier) @d)
        """.trimmingCharacters(in: .whitespaces)
        
        var source = ""
        source += patterns1
        source += patterns2
        source += patterns3
        
        let query = try! Query(language: lang.parser, source: source)
        
        XCTAssertEqual(query.startByteFor(pattern: 0), 0)
        XCTAssertEqual(query.startByteFor(pattern: 5), UInt32(patterns1.count))
        XCTAssertEqual(
            query.startByteFor(pattern: 7),
            UInt32(patterns1.count) + UInt32(patterns2.count)
        )
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
    ) -> [[Int: [[String]]]] {
        matches.map { match in
            [
                match.patternIndex: formatCaptures(
                    captures: match.captures,
                    query: query,
                    source: source
                )
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
    
    func toCallback(_ source: String) -> (Node) -> String {
        { node in
            node.utf8Text(source: source)
        }
    }
}

extension XCTestCase {
    func assert<T, E: Error & Equatable>(
        _ expression: @autoclosure () throws -> T,
        throws error: E,
        in file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var thrownError: Error?
        
        XCTAssertThrowsError(try expression(), file: file, line: line) {
            thrownError = $0
        }
        
        XCTAssertTrue(
            thrownError is E,
            "Unexpected error type: \(type(of: thrownError))",
            file: file, line: line
        )
        
        XCTAssertEqual(
            thrownError as? E, error,
            file: file, line: line
        )
    }
}
