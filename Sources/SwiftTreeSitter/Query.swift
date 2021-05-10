//
//  File.swift
//  
//
//  Created by Gustavo Ordaz on 7/25/20.
//

import Foundation
import TreeSitter

public struct QueryError: Error {
    public var row: Int
    public var column: Int
    public var offset: Int
    public var message: String
    public var kind: QueryErrorKind
}

public enum QueryErrorKind {
    case syntax
    case nodeType
    case field
    case capture
    case predicate
    case structure
}

extension QueryError: Equatable {
    public static func == (lhs: QueryError, rhs: QueryError) -> Bool {
        lhs.row == rhs.row
            && lhs.column == rhs.column
            && lhs.offset == rhs.offset
            && lhs.message == rhs.message
            && lhs.kind == rhs.kind
     }
}

public enum TextPredicate {
    case captureEqString(CUnsignedInt, String, Bool)
    case captureEqCapture(CUnsignedInt, CUnsignedInt, Bool)
    case captureMatchString(CUnsignedInt, String, Bool)
}

// MARK: - Query

public class Query {
    var pointer: OpaquePointer?
    private(set) public var captureNames = [String]()
    private(set) public var textPredicates = [TextPredicate]()
    private(set) public var propertySettings = [QueryProperty]()
    private(set) public var propertyPredicates = [(QueryProperty, Bool)]()
    private(set) public var generalPredicates = [QueryPredicate]()
    
    public init(language: Language, source: String) throws {
        var errorOffset: CUnsignedInt = 0
        var queryError = TSQueryErrorNone
        
        let queryPtr = ts_query_new(
            language.language,
            source,
            CUnsignedInt(source.utf8.count),
            &errorOffset,
            &queryError
        )
        
        // On failure, build an error based on the error code and offset.
        if queryPtr == nil {
            let offset = Int(errorOffset)
            var lineStart = 0
            var row = 0
            var lineContainingError: String? = .none
            for line in source.components(separatedBy: .newlines) {
                let lineEnd = lineStart + line.count + 1
                if lineEnd > offset {
                    lineContainingError = .some(line)
                    break
                } else {
                    lineStart = lineEnd
                    row += 1
                }
            }
            let column = offset - lineStart;
            
            let kind: QueryErrorKind
            let message: String
            switch queryError {
            // Error types that report names
            case TSQueryErrorNodeType, TSQueryErrorField, TSQueryErrorCapture:
                let startOffset = source.index(source.startIndex, offsetBy: offset)
                let suffix = source.suffix(from: startOffset)
                let endOffset = suffix.firstIndex { c in
                    !c.isNumber && !c.isLetter && c != "_" && c != "-"
                } ?? source.endIndex
                message = String(suffix.suffix(from: endOffset))
                switch queryError {
                case TSQueryErrorNodeType: kind = .nodeType
                case TSQueryErrorField: kind = .field
                case TSQueryErrorCapture: kind = .capture
                default: fatalError()
                };
            // Error types that report positions
            default:
                if let line = lineContainingError {
                    let padding = " "
                        .padding(
                            toLength: offset - lineStart,
                            withPad: " ",
                            startingAt: 0
                        )
                    message = "\(line)\n" + padding + "^"
                } else {
                    message = "Unexpected EOF"
                }
                switch queryError {
                case TSQueryErrorStructure: kind = QueryErrorKind.structure
                default: kind = QueryErrorKind.syntax
                }
            }
            throw QueryError(
                row: row,
                column: column,
                offset: offset,
                message: message,
                kind: kind
            )
        }
        
        let stringCount = ts_query_string_count(queryPtr)
        let captureCount = ts_query_capture_count(queryPtr)
        let patternCount = ts_query_pattern_count(queryPtr)
        
        captureNames.reserveCapacity(Int(stringCount))
        textPredicates.reserveCapacity(Int(patternCount))
        propertyPredicates.reserveCapacity(Int(patternCount))
        propertySettings.reserveCapacity(Int(patternCount))
        generalPredicates.reserveCapacity(Int(patternCount))
        
        // Build a vector of strings to store the capture names.
        for i in 0..<captureCount {
            var length: CUnsignedInt = 0
            let name = ts_query_capture_name_for_id(queryPtr, i, &length)
            captureNames.append(String(cString: name!))
        }
        
        // Build a vector of strings to represent literal values used in predicates.
        let stringValues: [String] = (0..<stringCount).map { i in
            var length: CUnsignedInt = 0
            let value = ts_query_string_value_for_id(queryPtr, i, &length)
            return String(cString: value!)
        }
        
        let typeDone = TSQueryPredicateStepTypeDone
        let typeCapture = TSQueryPredicateStepTypeCapture
        let typeString = TSQueryPredicateStepTypeString
        
        for i in 0..<patternCount {
            var length: CUnsignedInt = 0
            let rawPredicates = ts_query_predicates_for_pattern(
                queryPtr,
                i,
                &length
            )
            let predicateSteps: [UnsafeBufferPointer<TSQueryPredicateStep>.SubSequence] = {
                if length > 0 {
                    return UnsafeBufferPointer(
                        start: rawPredicates,
                        count: Int(length)
                    )
                    .split { $0.type == typeDone }
                }
                return []
            }()
            
            let byteOffset = ts_query_start_byte_for_pattern(queryPtr, CUnsignedInt(i))
            let idx = source.index(source.startIndex, offsetBy: Int(byteOffset))
            let row = source[...idx]
                .filter(\.isNewline)
                .components(separatedBy: .newlines)
                .count
            
            for p in predicateSteps where !p.isEmpty {
                let pred = Array(p)
                
                if pred[0].type != typeString {
                    let res = captureNames[Int(pred[0].value_id)]
                    
                    throw predicateError(row: row, message: """
                    Expected predicate to start with a function name.\
                    Got \(res).
                    """)
                }
                
                // Build a predicate for each of the known predicate function names.
                let operatorName = stringValues[Int(pred[0].value_id)]
                switch operatorName {
                case "eq?", "not-eq?":
                    if pred.count != 3 {
                        throw predicateError(row: row, message: """
                        Wrong number of arguments to #eq? predicate.
                        Expected 2, got \(pred.count - 1).
                        """)
                    }
                    if pred[1].type != typeCapture {
                        throw predicateError(row: row, message: """
                        First argument to #eq? predicate must be a capture name.
                        Got literal \"\(stringValues[Int(pred[1].value_id)])\".
                        """)
                    }
                    let isPositive = operatorName == "eq?";
                    textPredicates.append(
                        pred[2].type == typeCapture
                            ? .captureEqCapture(
                                pred[1].value_id,
                                pred[2].value_id,
                                isPositive
                            )
                            : .captureEqString(
                                pred[1].value_id,
                                stringValues[Int(pred[2].value_id)],
                                isPositive
                            )
                    )
                case "match?", "not-match?":
                    if pred.count != 3 {
                        throw predicateError(row: row, message: """
                        Wrong number of arguments to #match? predicate.
                        Expected 2, got \(pred.count - 1).
                        """)
                    }
                    if pred[1].type != typeCapture {
                        throw predicateError(row: row, message: """
                        First argument to #match? predicate must be a capture name.
                        Got literal \"\(stringValues[Int(pred[1].value_id)])\".
                        """)
                    }
                    if pred[2].type == typeCapture {
                        throw predicateError(row: row, message: """
                        Second argument to #match? predicate must be a literal.
                        Got capture \(captureNames[Int(pred[2].value_id)]).
                        """)
                    }
                    let isPositive = operatorName == "match?"
                    let regex = stringValues[Int(pred[2].value_id)];
                    textPredicates.append(
                        .captureMatchString(pred[1].value_id, regex, isPositive)
                    )
                case "set!":
                    propertySettings.append(
                        try parseProperty(
                            row: row,
                            functionName: operatorName,
                            captureNames: captureNames,
                            stringValues: stringValues,
                            args: pred[1...]
                        )
                    )
                case "is?", "is-not?":
                    propertyPredicates.append(
                        (
                            try parseProperty(
                                row: row,
                                functionName: operatorName,
                                captureNames: captureNames,
                                stringValues: stringValues,
                                args: pred[1...]
                            ),
                            operatorName == "is?"
                        )
                    )
                default:
                    generalPredicates.append(
                        QueryPredicate(
                            operator: operatorName,
                            args: pred[1...].map { step in
                                step.type == typeCapture
                                    ? .capture(step.value_id)
                                    : .string(stringValues[Int(step.value_id)])
                            }
                        )
                    )
                }
            }
        }
        self.pointer = queryPtr
    }
    
    deinit {
        ts_query_delete(pointer)
    }
    
    /// Get the byte offset where the given pattern starts in the query's source.
    public func startByteFor(pattern index: UInt) -> UInt {
        UInt(ts_query_start_byte_for_pattern(pointer, CUnsignedInt(index)))
    }
    
    /// Get the number of patterns in the query.
    public func patternCount() -> UInt {
        UInt(ts_query_pattern_count(pointer))
    }
    
    /// Get the properties that are checked for the given pattern index.
    ///
    /// This includes predicates with the operators `is?` and `is-not?`.
    public func propertyPredicate(at index: Int) -> (QueryProperty, Bool) {
        propertyPredicates[index]
    }
    
    /// Get the properties that are set for the given pattern index.
    ///
    /// This includes predicates with the operator `set!`.
    public func propertySettings(at index: Int) -> QueryProperty {
        propertySettings[index]
    }
    
    /// Get the other user-defined predicates associated with the given index.
    ///
    /// This includes predicate with operators other than:
    /// * `match?`
    /// * `eq?` and `not-eq?`
    /// * `is?` and `is-not?`
    /// * `set!`
    public func generalPredicates(at index: Int) -> QueryPredicate {
        generalPredicates[index]
    }
    
    /// Disable a certain capture within a query.
    ///
    /// This prevents the capture from being returned in matches, and also avoids any
    /// resource usage associated with recording the capture.
    public func disableCapture(name: String) {
        ts_query_disable_capture(pointer, name, CUnsignedInt(name.count))
    }
    
    /// Disable a certain pattern within a query.
    ///
    /// This prevents the pattern from matching, and also avoids any resource usage
    /// associated with the pattern.
    public func disablePattern(at index: Int) {
        ts_query_disable_pattern(pointer, CUnsignedInt(index))
    }
    
    /// Check if a given step in a query is 'definite'.
     ///
     /// A query step is 'definite' if its parent pattern will be guaranteed to match
     /// successfully once it reaches the step.
     public func stepIsDefinite(byteOffset: UInt) -> Bool {
         ts_query_step_is_definite(pointer, CUnsignedInt(byteOffset))
     }
    
    func parseProperty(
        row: Int,
        functionName: String,
        captureNames: [String],
        stringValues: [String],
        args: ArraySlice<TSQueryPredicateStep>
    ) throws -> QueryProperty {
        if args.isEmpty || args.count > 3 {
            throw predicateError(row: row, message: """
            Wrong number of arguments to \(functionName) predicate.
            Expected 1 to 3, got \(args.count).
            """)
        }
        
        var captureId: CUnsignedInt? = nil
        var key: String? = nil
        var value: String? = nil
        
        for arg in args {
            let index = Int(arg.value_id)
            if arg.type == TSQueryPredicateStepTypeCapture {
                if captureId != nil {
                    let name = captureNames[index]
                    throw predicateError(row: row, message: """
                    Invalid arguments to \(functionName) predicate.
                    Unexpected second capture name \(name)
                    """)
                }
                captureId = arg.value_id
            } else if key == nil {
                key = stringValues[index]
            } else if value == nil {
                value = stringValues[index]
            } else {
                let name = captureNames[index]
                throw predicateError(row: row, message: """
                Invalid arguments to \(functionName) predicate.
                Unexpected second capture name \(name)
                """)
            }
        }
        
        guard let theKey = key else {
            throw predicateError(row: row, message: """
            Invalid arguments to \(functionName) predicate.
            Missing key argument
            """)
        }
        
        return QueryProperty(key: theKey, value: value, captureId: captureId)
    }
}

func predicateError(row: Int, message: String) -> QueryError {
    QueryError(row: row, column: 0, offset: 0, message: message, kind: .predicate)
}

extension Query: Equatable {
    public static func == (lhs: Query, rhs: Query) -> Bool {
        lhs.pointer == rhs.pointer
    }
}

// MARK: - QueryCursor

/// A stateful object for executing a `Query` on a syntax `Tree`.
public class QueryCursor {
    var cursor: OpaquePointer
    
    public init() {
        self.cursor = ts_query_cursor_new()
    }
    
    deinit {
        ts_query_cursor_delete(cursor)
    }
    
    /// Check if, on its last execution, this cursor exceeded its maximum number of
    /// in-progress matches.
    public func didExceedMatchLimit() -> Bool {
        ts_query_cursor_did_exceed_match_limit(cursor)
    }
    
    /// Iterate over all of the matches in the order that they were found.
    ///
    /// Each match contains the index of the pattern that matched, and a list of captures.
    /// Because multiple patterns can match the same set of nodes, one match may contain
    /// captures that appear *before* some of the captures from a previous match.
    public func matches(
        query: Query,
        for node: Node,
        textCallback: @escaping (Node) -> String
    ) -> QueryMatches {
        exec(query: query, on: node)

        return QueryMatches(
            pointer: cursor,
            query: query,
            textCallback: textCallback
        )
    }
    
    /// Iterate over all of the individual captures in the order that they appear.
    ///
    /// This is useful if don't care about which pattern matched, and just want a single,
    /// ordered sequence of captures.
    public func captures(
        query: Query,
        for node: Node,
        textCallback: @escaping (Node) -> String
    ) -> QueryCaptures {
        exec(query: query, on: node)
        
        return QueryCaptures(
            pointer: cursor,
            query: query,
            textCallback: textCallback
        )
    }

    func exec(query: Query, on node: Node) {
        ts_query_cursor_exec(cursor, query.pointer, node.node)
    }

    /// Set the range in which the query will be executed, in terms of byte offsets.
    public func setByte(range: Range<UInt>) {
        ts_query_cursor_set_byte_range(
            cursor,
            CUnsignedInt(range.lowerBound),
            CUnsignedInt(range.upperBound)
        )
    }
    
    /// Set the range in which the query will be executed, in terms of rows and columns.
    public func setPoint(range: Range<Point>) {
        let start = range.lowerBound.rawPoint
        let end = range.upperBound.rawPoint
        ts_query_cursor_set_point_range(cursor, start, end)
    }
}

// MARK: - QueryProperty

/// A key-value pair associated with a particular pattern in a `Query`.
public struct QueryProperty {
    public let key: String
    public let value: String?
    public let captureId: UInt32?
}

// MARK: - QueryPredicate

/// A key-value pair associated with a particular pattern in a `Query`.
public struct QueryPredicate {
    public let `operator`: String
    public let args: [QueryPredicateArg]
}

public enum QueryPredicateArg {
    case capture(CUnsignedInt)
    case string(String)
}

// MARK: - QueryMatch

/// A match of a `Query` to a particular set of `Node`s.
public struct QueryMatch {
    public let patternIndex: Int
    public let captures: [QueryCapture]
    public let id: CUnsignedInt
    /// A pointer to TSQueryCursor
    public var cursor: OpaquePointer
    
    init(match: TSQueryMatch, cursor: OpaquePointer) {
        self.cursor = cursor
        self.id = match.id
        self.patternIndex = Int(match.pattern_index)
        if match.capture_count > 0 {
            self.captures = UnsafeBufferPointer(
                start: match.captures,
                count: Int(match.capture_count)
            )
            .map { QueryCapture(node: Node($0.node)!, index: $0.index) }
        } else {
            self.captures = []
        }
    }
    
    public func satisfiesTextPredicate(
        query: Query,
        textCallback: (Node) -> String
    ) -> Bool {
        if query.textPredicates.count > patternIndex {
            switch query.textPredicates[patternIndex] {
            case let .captureEqCapture(i, j, isPositive):
                let node1 = captureFor(index: i)!
                let node2 = captureFor(index: j)!
                return (textCallback(node1) == textCallback(node2)) == isPositive
            case let .captureEqString(i, s, isPositive):
                let node = captureFor(index: i)!
                return (textCallback(node) == s) == isPositive
            case let .captureMatchString(i, regex, isPositive):
                let node = captureFor(index: i)!
                return textCallback(node).matches(regex) == isPositive
            }
        }
        return true
    }
    
    func captureFor(index: CUnsignedInt) -> Node? {
        captures.first(where: { $0.index == index })?.node
    }
    
    public func remove() {
        ts_query_cursor_remove_match(cursor, id)
    }
}

// MARK: - QueryMatches

/// A sequence of `QueryMatch`.
public struct QueryMatches: Sequence {
    public var pointer: OpaquePointer
    public let query: Query
    public let textCallback: (Node) -> String
    
    public func makeIterator() -> QueryMatchesIterator {
        QueryMatchesIterator(self)
    }
    
    public struct QueryMatchesIterator: IteratorProtocol {
        let query: Query
        let textCallback: (Node) -> String
        let capture: QueryMatches
        
        init(_ capture: QueryMatches) {
            self.capture = capture
            self.query = capture.query
            self.textCallback = capture.textCallback
        }
        
        public func next() -> QueryMatch? {
            while true {
                let ptr = capture.pointer
                var match = TSQueryMatch()
                if ts_query_cursor_next_match(ptr, &match) {
                    let result = QueryMatch(match: match, cursor: capture.pointer)
                    if result.satisfiesTextPredicate(query: query, textCallback: textCallback) {
                        return result
                    }
                } else {
                    return nil
                }
            }
        }
    }
}
// MARK: - QueryCaptures

/// A sequence of `QueryCapture`s within a `QueryMatch`.
public struct QueryCaptures: Sequence {
    public var pointer: OpaquePointer
    public let query: Query
    public let textCallback: (Node) -> String
    
    public func makeIterator() -> QueryCapturesIterator {
        QueryCapturesIterator(self)
    }
    
    public struct QueryCapturesIterator: IteratorProtocol {
        let capture: QueryCaptures
        
        init(_ capture: QueryCaptures) {
            self.capture = capture
        }
        
        public func next() -> (QueryMatch, Int)? {
            while true {
                let ptr = capture.pointer
                var match = TSQueryMatch()
                var captureIndex = UInt32(0)
                if ts_query_cursor_next_capture(ptr, &match, &captureIndex) {
                    let result = QueryMatch(match: match, cursor: capture.pointer)
                    if result.satisfiesTextPredicate(query: capture.query, textCallback: capture.textCallback) {
                        return (result, Int(captureIndex))
                    } else {
                        result.remove();
                    }
                } else {
                    return nil
                }
            }
        }
    }
}

/// A particular `Node` that has been captured with a particular name within a `Query`.
public struct QueryCapture {
    public let node: Node
    public let index: UInt32
}

fileprivate extension String {
    func matches(_ regex: String) -> Bool {
        self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}
