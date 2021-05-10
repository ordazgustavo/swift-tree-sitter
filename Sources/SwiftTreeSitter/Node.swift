//
//  Node.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import Foundation
import TreeSitter

public struct Node {
    var node: TSNode
    
    public init?(_ node: TSNode) {
        if node.id == nil {
            return nil
        } else {
            self.node = node
        }
    }
    
    /// Get a numeric id for this node that is unique.
    ///
    /// Within a given syntax tree, no two nodes have the same id. However, if
    /// a new tree is created based on an older tree, and a node from the old
    /// tree is reused in the process, then that node will have the same id in
    /// both trees.
    public var id: Int {
        self.node.id.load(as: Int.self)
    }
    
    
    /// Get this node's type as a numerical id.
    public var kindId: CUnsignedShort {
        ts_node_symbol(node)
    }
    
    /// Get this node's type as a string.
    public var kind: String {
        String(cString: ts_node_type(node)!)
    }
    
    /// Get the `Language` that was used to parse this node's syntax tree.
    public var language: Language {
        Language(ts_tree_language(node.tree)!)
    }
    
    /// Check if this node is *named*.
    ///
    /// Named nodes correspond to named rules in the grammar, whereas
    /// *anonymous* nodes correspond to string literals in the grammar.
    public var isNamed: Bool {
        ts_node_is_named(node)
    }
    
    /// Check if this node is *extra*.
    ///
    /// Extra nodes represent things like comments, which are not required the
    /// grammar, but can appear anywhere.
    public func isExtra() -> Bool {
        ts_node_is_extra(node)
    }
    
    /// Check if this node has been edited.
    public func hasChanges() -> Bool {
        ts_node_has_changes(node)
    }
    
    /// Check if this node represents a syntax error or contains any syntax
    /// errors anywhere within it.
    public func hasError() -> Bool {
        ts_node_has_error(node)
    }
    
    /// Check if this node represents a syntax error.
    ///
    /// Syntax errors represent parts of the code that could not be incorporated
    /// into a valid syntax tree.
    public func isError() -> Bool {
        kindId == CUnsignedShort.max
    }
    
    /// Check if this node is *missing*.
    ///
    /// Missing nodes are inserted by the parser in order to recover from
    /// certain kinds of syntax errors.
    public func isMissing() -> Bool {
        ts_node_is_missing(node)
    }
    
    /// Get the byte offsets where this node starts.
    public var startByte: Int {
        Int(ts_node_start_byte(node))
    }
    
    /// Get the byte offsets where this node end.
    public var endByte: Int {
        Int(ts_node_end_byte(node))
    }
    
    /// Get the byte range of source code that this node represents.
    public var byteRange: Range<Int> {
        startByte..<endByte
    }
    
    /// Get the byte range of source code that this node represents.
    public var nsRange: NSRange {
        NSRange(location: startByte, length: endByte - startByte)
    }
    
    /// Get this node's start position in terms of rows and columns.
    public var startPosition: Point {
        Point(raw: ts_node_start_point(node))
    }
    
    /// Get this node's end position in terms of rows and columns.
    public var endPosition: Point {
        Point(raw: ts_node_end_point(node))
    }
    
    /// Get the range of source code that this node represents, both in terms of
    /// raw bytes and of row/column coordinates.
    public func range() -> STSRange {
        STSRange(
            startPoint: startPosition,
            endPoint: endPosition,
            startByte: ts_node_start_byte(node),
            endByte: ts_node_end_byte(node)
        )
    }
    
    /// Get the node's child at the given index, where zero represents the first
    /// child.
    ///
    /// This method is fairly fast, but its cost is technically log(i), so you
    /// if you might be iterating over a long list of children, you should use
    /// `Node.children(cursor:)` instead.
    ///
    /// - Parameter at: The index to look for
    /// - Returns: A posible node
    public func child(at: UInt) -> Node? {
        Node(ts_node_child(node, CUnsignedInt(at)))
    }
    
    /// Get this node's number of children.
    public var childCount: UInt {
        UInt(ts_node_child_count(node))
    }
    
    /// Get this node's *named* child at the given index.
    ///
    /// See also `Node.isNamed`.
    /// This method is fairly fast, but its cost is technically log(i), so you
    /// if you might be iterating over a long list of children, you should use
    /// `Node.namedChildren(cursor:)` instead.
    ///
    /// - Parameter at: The index to look for
    /// - Returns: A posible node
    public func namedChild(at: UInt) -> Node? {
        Node(ts_node_named_child(node, CUnsignedInt(at)))
    }
    
    /// Get this node's number of *named* children.
    ///
    /// See also `Node.isNamed`.
    public var namedChildCount: UInt {
        UInt(ts_node_named_child_count(node))
    }
    
    /// Get the first child with the given field name.
    ///
    /// If multiple children may have the same field name, access them using
    /// `Node.childrenBy(fieldName:cursor:)`
    ///
    /// - Parameter fieldName: The name to look for
    /// - Returns: A posible node
    public func childBy(fieldName: String) -> Node? {
        Node(ts_node_child_by_field_name(
                node,
                fieldName,
                CUnsignedInt(fieldName.count)
            )
        )
    }
    
    /// Get this node's child with the given numerical field id.
    ///
    /// See also `Node.childBy(fieldName:cursor:)`. You can convert a field name
    /// to an id using `Language.fieldIdFor(fieldName:)`.
    ///
    /// - Parameter fieldId: The language field identifier
    /// - Returns: A posible node
    public func childBy(fieldId: UInt16) -> Node? {
        Node(ts_node_child_by_field_id(node, CUnsignedShort(fieldId)))
    }
    
    /// Iterate over this node's children.
    ///
    /// A `TreeCursor` is used to retrieve the children efficiently. Obtain
    /// a `TreeCursor` by calling `Tree.walk()` or `Node.walk()`. To avoid
    /// unnecessary allocations, you should reuse the same cursor for subsequent
    /// calls to this method.
    ///
    /// If you're walking the tree recursively, you may want to use the
    /// `TreeCursor` APIs directly instead.
    public func children(cursor: inout TreeCursor) -> [Node] {
        cursor.reset(node: self)
        cursor.gotoFirstChild()
        let range = 0..<childCount
        
        return range.map { _ in
            let result = cursor.node
            cursor.gotoNextSibling()
            return result
        }
    }
    
    /// Iterate over this node's named children.
    ///
    /// See also `Node.children(cursor:)`.
    public func namedChildren(cursor: inout TreeCursor) -> [Node] {
        cursor.reset(node: self)
        cursor.gotoFirstChild()
        let range = 0..<namedChildCount
        
        return range.map { _ in
            while !cursor.node.isNamed {
                if !cursor.gotoNextSibling() {
                    break
                }
            }
            let result = cursor.node
            cursor.gotoNextSibling()
            return result
        }
    }
    
    /// Iterate over this node's children with a given field name.
    ///
    /// See also `Node.children(cursor:)`.
    public func childrenBy(fieldName: String, cursor: inout TreeCursor) -> [Node] {
        let fieldId = language.fieldIdFor(fieldName: fieldName)
        return childrenBy(fieldId: fieldId ?? 0, cursor: &cursor)
    }

    /// Iterate over this node's children with a given field id.
    ///
    /// See also `Node.childrenBy(fieldName:cursor:)`.
    public func childrenBy(
        fieldId: UInt16,
        cursor: inout TreeCursor
    ) -> [Node] {
        cursor.reset(node: self)
        cursor.gotoFirstChild()
        var done = false
        var nodes = [Node]()
        while !done {
            while cursor.fieldId() != fieldId {
                if !cursor.gotoNextSibling() {
                    break
                }
            }
            let result = cursor.node
            if !cursor.gotoNextSibling() {
                done = true
            }
            nodes.append(result)
        }
        return nodes
    }
    
    /// Get this node's immediate parent.
    public var parent: Node? {
        Node(ts_node_parent(node))
    }

    /// Get this node's next sibling.
    public var nextSibling: Node? {
        Node(ts_node_next_sibling(node))
    }
    
    /// Get this node's previous sibling.
    public var prevSibling: Node? {
        Node(ts_node_prev_sibling(node))
    }

    /// Get this node's next named sibling.
    public var nextNamedSibling: Node? {
        Node(ts_node_next_named_sibling(node))
    }
    
    /// Get this node's previous named sibling.
    public var prevNamedSibling: Node? {
        Node(ts_node_prev_named_sibling(node))
    }
    
    public func descendantFor(
        startByte: Int,
        endByte: Int
    ) -> Node? {
        Node(
            ts_node_descendant_for_byte_range(
                node,
                CUnsignedInt(startByte),
                CUnsignedInt(endByte)
            )
        )
    }
    
    /// Get the smallest node within this node that spans the given range.
    public func descendant(for byteRange: Range<Int>) -> Node? {
        descendantFor(
            startByte: byteRange.lowerBound,
            endByte: byteRange.upperBound
        )
    }
    
    /// Get the smallest node within this node that spans the given range.
    public func descendant(for nsRange: NSRange) -> Node? {
        descendantFor(
            startByte: nsRange.lowerBound,
            endByte: nsRange.upperBound
        )
    }
    
    /// Get the smallest named node within this node that spans the given range.
    public func namedDescendantFor(
        startByte: Int,
        endByte: Int
    ) -> Node? {
        Node(
            ts_node_named_descendant_for_byte_range(
                node,
                CUnsignedInt(startByte),
                CUnsignedInt(endByte)
            )
        )
    }

    /// Get the smallest named node within this node that spans the given range.
    public func namedDescendant(for byteRange: Range<Int>) -> Node? {
        namedDescendantFor(
            startByte: byteRange.lowerBound,
            endByte: byteRange.upperBound
        )
    }
    
    /// Get the smallest named node within this node that spans the given range.
    public func namedDescendant(for nsRange: NSRange) -> Node? {
        namedDescendantFor(
            startByte: nsRange.lowerBound,
            endByte: nsRange.upperBound
        )
    }
    
    /// Get the smallest node within this node that spans the given range.
    public func descendant(for pointRange: Range<Point>) -> Node? {
        Node(
            ts_node_descendant_for_point_range(
                node,
                pointRange.lowerBound.rawPoint,
                pointRange.upperBound.rawPoint
            )
        )
    }
    
    /// Get the smallest named node within this node that spans the given range.
    public func namedDescendant(for pointRange: Range<Point>) -> Node? {
        Node(
            ts_node_named_descendant_for_point_range(
                node,
                pointRange.lowerBound.rawPoint,
                pointRange.upperBound.rawPoint
            )
        )
    }
    
    public func toSexp() -> String {
        let cString = ts_node_string(node)
        let result = String(cString: cString!)
        return result
    }

    /// Get a utf8 string representation of this node
    public func utf8Text(source: String) -> String {
        let utf8 = Array(source.utf8)[Int(startByte)..<Int(endByte)]
        
        return String(decoding: utf8, as: UTF8.self)
    }
    
    /// Get a utf16 string representation of this node
    public func utf16Text(source: String) -> String {
        let utf16 = Array(source.utf16)[Int(startByte)..<Int(endByte)]
        
        return String(decoding: utf16, as: UTF16.self)
    }
    
    /// Create a new `TreeCursor` starting from this node.
    public func walk() -> TreeCursor {
        TreeCursor(ts_tree_cursor_new(node))
    }

    /// Edit this node to keep it in-sync with source code that has been edited.
    ///
    /// This function is only rarely needed. When you edit a syntax tree with
    /// the `Tree.edit(_:)` method, all of the nodes that you retrieve from the
    /// tree afterward will already reflect the edit. You only need to use
    /// `Node.edit(_:)` when you have a specific `Node` instance that you want
    /// to keep and continue to use after an edit.
    public mutating func edit(_ inputEdit: inout InputEdit) {
        ts_node_edit(&node, &inputEdit.rawInputEdit)
    }
    
    /// Edit this node to keep it in-sync with source code that has been edited.
    ///
    /// This function is only rarely needed. When you edit a syntax tree with
    /// the `Tree.edit(_:)` method, all of the nodes that you retrieve from the
    /// tree afterward will already reflect the edit. You only need to use
    /// `Node.edit(_:)` when you have a specific `Node` instance that you want
    /// to keep and continue to use after an edit.
    public mutating func edit(_ inputEdit: @autoclosure () -> InputEdit) {
        var edit = inputEdit()
        ts_node_edit(&node, &edit.rawInputEdit)
    }
}

extension Node: Equatable {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }
}

extension Node: Hashable {
    public func hash(into hasher: inout Hasher) {
        self.node.id.hash(into: &hasher)
        self.node.context.0.hash(into: &hasher)
        self.node.context.1.hash(into: &hasher)
        self.node.context.2.hash(into: &hasher)
        self.node.context.3.hash(into: &hasher)
    }
}
