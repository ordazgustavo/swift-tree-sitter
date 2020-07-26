//
//  File.swift
//  
//
//  Created by Gustavo Ordaz on 7/25/20.
//

import TreeSitter

public class Query {
    var query: OpaquePointer
    var errorOffset: UInt32
    var queryError: TSQueryError
    
    public init(language: Language, source: String) {
        var errorOffset = UInt32(0)
        var queryError: TSQueryError = .init(0)
        self.query = withUnsafeMutablePointer(to: &errorOffset) { errOffset in
            withUnsafeMutablePointer(to: &queryError) { qError in
                ts_query_new(
                    language.language,
                    source,
                    UInt32(source.count),
                    errOffset,
                    qError
                )
            }
        }
        self.errorOffset = errorOffset
        self.queryError = queryError
    }
    
    deinit {
        ts_query_delete(query)
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

/**
 * Create a new cursor for executing a given query.
 *
 * The cursor stores the state that is needed to iteratively search
 * for matches. To use the query cursor, first call `ts_query_cursor_exec`
 * to start running a given query on a given syntax node. Then, there are
 * two options for consuming the results of the query:
 * 1. Repeatedly call `ts_query_cursor_next_match` to iterate over all of the
 *    the *matches* in the order that they were found. Each match contains the
 *    index of the pattern that matched, and an array of captures. Because
 *    multiple patterns can match the same set of nodes, one match may contain
 *    captures that appear *before* some of the captures from a previous match.
 * 2. Repeatedly call `ts_query_cursor_next_capture` to iterate over all of the
 *    individual *captures* in the order that they appear. This is useful if
 *    don't care about which pattern matched, and just want a single ordered
 *    sequence of captures.
 *
 * If you don't care about consuming all of the results, you can stop calling
 * `ts_query_cursor_next_match` or `ts_query_cursor_next_capture` at any point.
 *  You can then start executing another query on another node by calling
 *  `ts_query_cursor_exec` again.
 */
public class QueryCursor {
    var cursor: OpaquePointer
    
    public init() {
        self.cursor = ts_query_cursor_new()
    }
    
    deinit {
        ts_query_cursor_delete(cursor)
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

