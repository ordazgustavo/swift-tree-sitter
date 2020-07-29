//
//  File.swift
//  
//
//  Created by Gustavo Ordaz on 7/25/20.
//

import Foundation
import TreeSitter

public enum QueryError: Error {
    case syntax(Int, String)
    case nodeType(Int, String)
    case field(Int, String)
    case capture(Int, String)
    case predicate(String)
}

extension QueryError: Equatable {
    public static func ==(lhs: QueryError, rhs: QueryError) -> Bool {
         switch (lhs, rhs) {
         case (.syntax(let lInt, let lString), .syntax(let rInt, let rString)):
            return lInt == rInt && lString == rString
            
         case (.nodeType(let lInt, let lString), .nodeType(let rInt, let rString)):
            return lInt == rInt && lString == rString
            
         case (.field(let lInt, let lString), .field(let rInt, let rString)):
            return lInt == rInt && lString == rString
            
         case (.capture(let lInt, let lString), .capture(let rInt, let rString)):
            return lInt == rInt && lString == rString
            
         case (.predicate(let lString), .predicate(let rString)):
            return lString == rString
            
         default:
            return false
         }
     }
}

public enum TextPredicate {
    case captureEqString(UInt32, String, Bool)
    case captureEqCapture(UInt32, UInt32, Bool)
    case captureMatchString(UInt32, String, Bool)
}

// MARK: - Query

public class Query {
    public var query: OpaquePointer?
    public var source: String
    public var errorOffset: UInt32
    public var queryError: TSQueryError
    public var captureNames = [String]()
    public var textPredicates = [TextPredicate]()
    public var propertySettings = [QueryProperty]()
    public var propertyPredicates = [(QueryProperty, Bool)]()
    public var generalPredicates = [QueryPredicate]()
    
    public init(language: Language, source: String) {
        var errorOffset = UInt32(0)
        var queryError = TSQueryErrorNone
        self.query = ts_query_new(
            language.language,
            source,
            UInt32(source.count),
            &errorOffset,
            &queryError
        )
        self.source = source
        self.errorOffset = errorOffset
        self.queryError = queryError
    }
    
    deinit {
        ts_query_delete(query)
    }
    
    public func build() -> Result<Query, QueryError> {
        // On failure, build an error based on the error code and offset.
        if query == nil {
            let offset = Int(errorOffset)
            var lineStart = 0
            var row = 0
            let lineContainingError = source.components(separatedBy: "\n").first { line in
                row += 1
                let lineEnd = lineStart + line.count + 1
                if lineEnd > offset {
                    return true
                } else {
                    lineStart = lineEnd
                    return false
                }
            }
            
            var message = "Unexpected EOF"
            if let line = lineContainingError {
                let padding = " ".padding(toLength: offset - lineStart, withPad: " ", startingAt: 0)
                message = "\(line)\n" + padding + "^"
            }
            
            if queryError != TSQueryErrorSyntax {
                let firstHalf = source.index(source.startIndex, offsetBy: offset)
                let suffix = String(source[firstHalf...])
                let endOffset = suffix.first { (c) -> Bool in
                    !(c.isNumber || c.isLetter) && c != "_" && c != "-"
                }
                let name = suffix.split(maxSplits: 1, omittingEmptySubsequences: false) {
                    $0 == endOffset
                }[0]
                
                switch queryError {
                case TSQueryErrorNodeType:
                    return .failure(.nodeType(row, String(name)))
                case TSQueryErrorField:
                    return .failure(.nodeType(row, String(name)))
                case TSQueryErrorCapture:
                    return .failure(.nodeType(row, String(name)))
                default:
                    return .failure(.syntax(row, message))
                }
            } else {
                return .failure(.syntax(row, message))
            }
        }
        
        let stringCount = getStringCount()
        let captureCount = getCaptureCount()
        let patternCount = getPatternCount()
        
        // Build a vector of strings to store the capture names.
        for i in 0..<captureCount {
            var length = UInt32(0)
            let name = getCaptureName(for: i, length: &length)
            captureNames.append(name!)
        }
        
        // Build a vector of strings to represent literal values used in predicates.
        let stringValues: [String] = (0..<stringCount).compactMap { i in
            var length = UInt32(0)
            return getStringValue(for: i, length: &length)
        }
        
        // Build a vector of predicates for each pattern.
        for i in 0..<patternCount {
            var length = UInt32(0)
            let rawPredicates = withUnsafeMutablePointer(to: &length) {
                ts_query_predicates_for_pattern(query, i, $0)
            }
            let predicateSteps = UnsafeBufferPointer(start: rawPredicates, count: Int(length))
            
            let typeDone = TSQueryPredicateStepTypeDone
            let typeCapture = TSQueryPredicateStepTypeCapture
            let typeString = TSQueryPredicateStepTypeString
            
            for p in predicateSteps.split(whereSeparator: { $0.type == typeDone }) {
                let pred = Array(p)
                if pred.isEmpty {
                    continue
                }
                
                if pred[0].type != typeString {
                    let res = captureNames[Int(pred[0].value_id)]
                    return .failure(
                        .predicate("Expected predicate to start with a function name. Got \(res).")
                    )
                }
                
                // Build a predicate for each of the known predicate function names.
                let operatorName = stringValues[Int(pred[0].value_id)]
                
                if operatorName == "eq?" || operatorName == "not-eq?" {
                    if pred.count != 3 {
                        return .failure(
                            .predicate("Wrong number of arguments to #eq? predicate. Expected 2, got \(pred.count - 1).")
                        )
                    }
                    if pred[1].type != typeCapture {
                        return .failure(
                            .predicate("First argument to #eq? predicate must be a capture name. Got literal \"\(stringValues[Int(pred[1].value_id)])\".")
                        )
                    }
                    let isPositive = operatorName == "eq?";
                    if pred[2].type == typeCapture {
                        textPredicates.append(
                            .captureEqCapture(pred[1].value_id, pred[2].value_id, isPositive)
                        )
                    } else {
                        textPredicates.append(
                            .captureEqString(pred[1].value_id, stringValues[Int(pred[2].value_id)], isPositive)
                        )
                    }
                } else if operatorName == "match?" || operatorName == "not-match?" {
                    if pred.count != 3 {
                        return .failure(
                            .predicate("Wrong number of arguments to #match? predicate. Expected 2, got \(pred.count - 1).")
                        )
                    }
                    if pred[1].type != typeCapture {
                        return .failure(
                            .predicate("First argument to #match? predicate must be a capture name. Got literal \"\(stringValues[Int(pred[1].value_id)])\".")
                        )
                    }
                    if pred[2].type == typeCapture {
                        return .failure(
                            .predicate("Second argument to #match? predicate must be a literal. Got capture \(captureNames[Int(pred[2].value_id)]).")
                        )
                    }
                    let isPositive = operatorName == "match?"
                    let regex = stringValues[Int(pred[2].value_id)];
                    textPredicates.append(.captureMatchString(pred[1].value_id, regex, isPositive))
                } else if operatorName == "set!" {
                    let prop = try! parseProperty(
                        functionName: "set!",
                        captureNames: captureNames,
                        stringValues: stringValues,
                        args: Array(pred[1...])
                    ).get()
                    propertySettings.append(prop)
                } else if operatorName == "is?" || operatorName == "is-not?" {
                    let prop = try! parseProperty(
                        functionName: operatorName,
                        captureNames: captureNames,
                        stringValues: stringValues,
                        args: Array(pred[1...])
                    ).get()
                    propertyPredicates.append((prop, operatorName == "is?"))
                } else {
                    let args: [QueryPredicateArg] = pred[1...].map { step in
                        step.type == typeCapture
                            ? .capture(step.value_id)
                            : .string(stringValues[Int(step.value_id)])
                    }
                    let pred = QueryPredicate(
                        operator: operatorName,
                        args: args
                    )
                    generalPredicates.append(pred)
                }
            }
        }
        return .success(self)
    }
    
    public func parseProperty(
        functionName: String,
        captureNames: [String],
        stringValues: [String],
        args: [TSQueryPredicateStep]
    ) -> Result<QueryProperty, QueryError> {
        if args.count == 0 || args.count > 3 {
            return .failure(
                .predicate("Wrong number of arguments to \(functionName) predicate. Expected 1 to 3, got \(args.count).")
            )
        }
        
        var captureId: UInt32? = nil
        var key: String? = nil
        var value: String? = nil
        
        for arg in args {
            if arg.type == TSQueryPredicateStepTypeCapture {
                if captureId != nil {
                    let name = captureNames[Int(arg.value_id)]
                    return .failure(
                        .predicate("Invalid arguments to \(functionName) predicate. Unexpected second capture name \(name)")
                    )
                }
                captureId = arg.value_id
            } else if key == nil {
                key = stringValues[Int(arg.value_id)]
            } else if value == nil {
                value = stringValues[Int(arg.value_id)]
            } else {
                let name = captureNames[Int(arg.value_id)]
                return .failure(
                    .predicate("Invalid arguments to \(functionName) predicate. Unexpected second capture name \(name)")
                )
            }
        }
        
        guard let theKey = key else {
            return .failure(
                .predicate("Invalid arguments to \(functionName) predicate. Missing key argument")
            )
        }
        
        return .success(.init(key: theKey, value: value, captureId: captureId))
    }
    
    
    /// Get the number of patterns in the query.
    public func getPatternCount() -> UInt32 {
        ts_query_pattern_count(query)
    }
    
    /// Get the number of captures in the query.
    public func getCaptureCount() -> UInt32 {
        ts_query_capture_count(query)
    }
    
    /// Get the number of string literals in the query.
    public func getStringCount() -> UInt32 {
        ts_query_string_count(query)
    }
    
    ///
    /// Get the byte offset where the given pattern starts in the query's source.
    ///
    /// This can be useful when combining queries by concatenating their source
    /// code strings.
    ///
    public func getPatternStartOffset(from: UInt32) -> UInt32 {
        ts_query_start_byte_for_pattern(query, from)
    }
    
    /**
     * Get all of the predicates for the given pattern in the query.
     *
     * The predicates are represented as a single array of steps. There are three
     * types of steps in this array, which correspond to the three legal values for
     * the `type` field:
     * - `TSQueryPredicateStepTypeCapture` - Steps with this type represent names
     *    of captures. Their `value_id` can be used with the
     *   `ts_query_capture_name_for_id` function to obtain the name of the capture.
     * - `TSQueryPredicateStepTypeString` - Steps with this type represent literal
     *    strings. Their `value_id` can be used with the
     *    `ts_query_string_value_for_id` function to obtain their string value.
     * - `TSQueryPredicateStepTypeDone` - Steps with this type are *sentinels*
     *    that represent the end of an individual predicate. If a pattern has two
     *    predicates, then there will be two steps with this `type` in the array.
     */
    public func getQueryPredicatesForPattern(start: UInt32, length: inout UInt32) -> TSQueryPredicateStep? {
        let res = ts_query_predicates_for_pattern(query, start, &length)
        
        return res?.pointee
    }
    
    /**
     * Get the name and length of one of the query's captures, or one of the
     * query's string literals. Each capture and string is associated with a
     * numeric id based on the order that it appeared in the query's source.
     */
    public func getCaptureName(for id: UInt32, length: inout UInt32) -> String? {
        let res = ts_query_capture_name_for_id(query, id, &length)

        guard let cStr = res else { return nil }
        
        return String(cString: cStr)
    }
    
    /**
     * Get the name and length of one of the query's captures, or one of the
     * query's string literals. Each capture and string is associated with a
     * numeric id based on the order that it appeared in the query's source.
     */
    public func getStringValue(for id: UInt32, length: inout UInt32) -> String? {
        let res = ts_query_string_value_for_id(query, id, &length)
        
        guard let cStr = res else { return nil }
        
        return String(cString: cStr)
    }
    
    /**
     * Disable a certain capture within a query.
     *
     * This prevents the capture from being returned in matches, and also avoids
     * any resource usage associated with recording the capture. Currently, there
     * is no way to undo this.
     */
    public func disableCapture(name: String, at position: UInt32) {
        ts_query_disable_capture(query, name, position)
    }

    /**
     * Disable a certain pattern within a query.
     *
     * This prevents the pattern from matching and removes most of the overhead
     * associated with the pattern. Currently, there is no way to undo this.
     */
    public func disablePattern(at position: UInt32) {
        ts_query_disable_pattern(query, position)
    }
}

extension Query: Equatable {
    public static func == (lhs: Query, rhs: Query) -> Bool {
        lhs.query == rhs.query
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

        return .init(pointer: cursor, query: query, textCallback: textCallback)
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
        
        return .init(pointer: cursor, query: query, textCallback: textCallback)
    }

    /**
     * Start running a given query on a given node.
     */
    public func exec(query: Query, on node: Node) {
        ts_query_cursor_exec(cursor, query.query, node.node)
    }

    /**
     * Set the range of bytes positions in which the query
     * will be executed.
     */
    public func setByte(range: Range<UInt32>) {
        ts_query_cursor_set_byte_range(cursor, range.lowerBound, range.upperBound)
    }
    
    /**
     * Set the range of ponts (row, column) positions in which the query
     * will be executed.
     */
    public func setPointRange(start: TSPoint, end: TSPoint) {
        ts_query_cursor_set_point_range(cursor, start, end)
    }

    /**
     * Advance to the next match of the currently running query.
     *
     * If there is a match, write it to `match` and return `true`.
     * Otherwise, return `false`.
     */
    public func gotoNextMatch(match: inout TSQueryMatch) -> Bool {
        ts_query_cursor_next_match(cursor, &match)
    }
    
    public func removeMatch(id: UInt32) {
        ts_query_cursor_remove_match(cursor, id)
    }
    
    /**
     * Advance to the next capture of the currently running query.
     *
     * If there is a capture, write its match to `match` and its index within
     * the matche's capture list to `index`. Otherwise, return `false`.
     */
    public func gotoNextCapture(match: inout TSQueryMatch, index: inout UInt32) -> Bool {
        ts_query_cursor_next_capture(cursor, &match, &index)
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
    case capture(UInt32)
    case string(String)
}

// MARK: - QueryMatch

/// A match of a `Query` to a particular set of `Node`s.
public struct QueryMatch {
    public let patternIndex: Int
    public let captures: [QueryCapture]
    public let id: UInt32
    /// A pointer to TSQueryCursor
    public var cursor: OpaquePointer
    
    init(match: TSQueryMatch, cursor: OpaquePointer) {
        self.cursor = cursor
        self.id = match.id
        self.patternIndex = Int(match.pattern_index)
        let caps = UnsafeBufferPointer(start: match.captures, count: Int(match.capture_count))
        let captures = Array(caps).map { QueryCapture(node: Node($0.node)!, index: $0.index) }
        self.captures = captures
    }
    
    public func satisfiesTextPredicate(
        query: Query,
        textCallback: (Node) -> String
    ) -> Bool {
        if query.textPredicates.count > patternIndex {
            switch query.textPredicates[patternIndex] {
            case .captureEqCapture(let i, let j, let isPositive):
                let node1 = captureFor(index: i)!
                let node2 = captureFor(index: j)!
                return (textCallback(node1) == textCallback(node2)) == isPositive
            case .captureEqString(let i, let s, let isPositive):
                let node = captureFor(index: i)!
                return (textCallback(node) == s) == isPositive
            case .captureMatchString(let i, let regex, let isPositive):
                let node = captureFor(index: i)!
                return textCallback(node).matches(regex) == isPositive
            }
        }
        return false
    }
    
    func captureFor(index: UInt32) -> Node? {
        for c in captures where c.index == index {
            return c.node
        }
        
        return nil
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
}

public struct QueryMatchesIterator: IteratorProtocol {
    let capture: QueryMatches
    
    init(_ capture: QueryMatches) {
        self.capture = capture
    }
    
    public func next() -> QueryMatch? {
        while true {
            var match = TSQueryMatch()
            let ptr = capture.pointer
            let canGo = ts_query_cursor_next_match(ptr, &match)
            if canGo {
                return QueryMatch(match: match, cursor: capture.pointer)
            } else {
                return nil
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
}

public struct QueryCapturesIterator: IteratorProtocol {
    let capture: QueryCaptures
    
    init(_ capture: QueryCaptures) {
        self.capture = capture
    }
    
    public func next() -> (QueryMatch, Int)? {
        while true {
            var captureIndex = UInt32(0)
            var match = TSQueryMatch()
            let ptr = capture.pointer
            let canGo = ts_query_cursor_next_capture(ptr, &match, &captureIndex)
            if canGo {
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
