//
//  Node.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

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
    public func id() -> Int32 {
        self.node.id.load(as: Int32.self)
    }
    
    /// Get this node's type as a numerical id.
    public func kindId() -> UInt16 {
        ts_node_symbol(node)
    }
    
    /// Get this node's type as a string.
    public func kind() -> String {
        String(cString: ts_node_type(node)!)
    }
    
    /// Get the [Language] that was used to parse this node's syntax tree.
    public func language() -> Language {
        Language(ts_tree_language(self.node.tree)!)
    }
    
    /// Check if this node is *named*.
    ///
    /// Named nodes correspond to named rules in the grammar, whereas *anonymous* nodes
    /// correspond to string literals in the grammar.
    public func isNamed() -> Bool {
        ts_node_is_named(node)
    }
    
    /// Check if this node is *extra*.
    ///
    /// Extra nodes represent things like comments, which are not required the grammar,
    /// but can appear anywhere.
    public func isExtra() -> Bool {
        ts_node_is_extra(node)
    }
    
    /// Check if this node has been edited.
    public func hasChanges() -> Bool {
        ts_node_has_changes(node)
    }
    
    /// Check if this node represents a syntax error or contains any syntax errors anywhere
    /// within it.
    public func hasError() -> Bool {
        ts_node_has_error(node)
    }
    
    /// Check if this node represents a syntax error.
    ///
    /// Syntax errors represent parts of the code that could not be incorporated into a
    /// valid syntax tree.
    public func isError() -> Bool {
        kindId() == UInt16.max
    }
    
    /// Check if this node is *missing*.
    ///
    /// Missing nodes are inserted by the parser in order to recover from certain kinds of
    /// syntax errors.
    public func isMissing() -> Bool {
        ts_node_is_missing(node)
    }
    
    /// Get the byte offsets where this node starts.
    public func startByte() -> UInt32 {
        ts_node_start_byte(node)
    }
    
    /// Get the byte offsets where this node end.
    public func endByte() -> UInt32 {
        ts_node_end_byte(node)
    }
    
    /// Get the byte range of source code that this node represents.
    public func byteRange() -> Range<UInt32> {
        startByte()..<endByte()
    }
    
    /// Get this node's start position in terms of rows and columns.
    public func startPosition() -> TSPoint {
        ts_node_start_point(node)
    }
    
    /// Get this node's end position in terms of rows and columns.
    public func endPosition() -> TSPoint {
        ts_node_end_point(node)
    }
    
    /// Get the range of source code that this node represents, both in terms of raw bytes
    /// and of row/column coordinates.
    public func range() -> TSRange {
        TSRange(
            start_point: startPosition(),
            end_point: endPosition(),
            start_byte: startByte(),
            end_byte: endByte()
        )
    }
    
    /// Get the node's child at the given index, where zero represents the first
    /// child.
    ///
    /// This method is fairly fast, but its cost is technically log(i), so you
    /// if you might be iterating over a long list of children, you should use
    /// [Node::children] instead.
    public func child(at: UInt32) -> Node? {
        Node(ts_node_child(node, at))
    }
    
    /// Get this node's number of children.
    public func childCount() -> UInt32 {
        ts_node_child_count(node)
    }
    
    /// Get this node's *named* child at the given index.
    ///
    /// See also [Node::is_named].
    /// This method is fairly fast, but its cost is technically log(i), so you
    /// if you might be iterating over a long list of children, you should use
    /// [Node::named_children] instead.
    public func namedChild(at: UInt32) -> Node? {
        Node(ts_node_named_child(node, at))
    }
    
    /// Get this node's number of *named* children.
    ///
    /// See also [Node::is_named].
    public func namedChildCount() -> UInt32 {
        ts_node_named_child_count(node)
    }
    
    /// Get the first child with the given field name.
    ///
    /// If multiple children may have the same field name, access them using
    /// [children_by_field_name](Node::children_by_field_name)
    public func childBy(fieldName: String) -> Node? {
        Node(ts_node_child_by_field_name(
                node,
                fieldName,
                uint(fieldName.count)
            )
        )
    }
    
    /// Get this node's child with the given numerical field id.
    ///
    /// See also [child_by_field_name](Node::child_by_field_name). You can convert a field name to
    /// an id using [Language::field_id_for_name].
    public func childBy(fieldId: ushort) -> Node? {
        Node(ts_node_child_by_field_id(node, fieldId))
    }
    
    /// Iterate over this node's children.
    ///
    /// A [TreeCursor] is used to retrieve the children efficiently. Obtain
    /// a [TreeCursor] by calling [Tree::walk] or [Node::walk]. To avoid unnecessary
    /// allocations, you should reuse the same cursor for subsequent calls to
    /// this method.
    ///
    /// If you're walking the tree recursively, you may want to use the `TreeCursor`
    /// APIs directly instead.
    public func children(cursor: inout TreeCursor) -> [Node] {
        cursor.reset(node: self)
        cursor.gotoFirstChild()
        let range = 0..<childCount()
        
        return range.map { _ in
            let result = cursor.node()
            cursor.gotoNextSibling()
            return result
        }
    }
    
    
    /// Iterate over this node's named children.
    ///
    /// See also [Node::children].
    public func namedChildren(cursor: inout TreeCursor) -> [Node] {
        cursor.reset(node: self)
        cursor.gotoFirstChild()
        let range = 0..<namedChildCount()
        
        return range.map { _ in
            while !cursor.node().isNamed() {
                if !cursor.gotoNextSibling() {
                    break
                }
            }
            let result = cursor.node()
            cursor.gotoNextSibling()
            return result
        }
    }
    
    /// Iterate over this node's children with a given field name.
    ///
    /// See also [Node::children].
    public func childrenBy(fieldName: String, cursor: inout TreeCursor) -> [Node] {
        let fieldId = language().fieldIdFor(fieldName: fieldName)
        return childrenBy(fieldId: fieldId ?? 0, cursor: &cursor)
    }

    /// Iterate over this node's children with a given field id.
    ///
    /// See also [Node::children_by_field_name].
    public func childrenBy(fieldId: UInt16, cursor: inout TreeCursor) -> [Node] {
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
            let result = cursor.node()
            if !cursor.gotoNextSibling() {
                done = true
            }
            nodes.append(result)
        }
        return nodes
    }
    
    /// Get this node's immediate parent.
    public func parent() -> Node? {
        Node(ts_node_parent(node))
    }

    /// Get this node's next sibling.
    public func nextSibling() -> Node? {
        Node(ts_node_next_sibling(node))
    }
    
    /// Get this node's previous sibling.
    public func prevSibling() -> Node? {
        Node(ts_node_prev_sibling(node))
    }

    /// Get this node's next named sibling.
    public func nextNamedSibling() -> Node? {
        Node(ts_node_next_named_sibling(node))
    }
    
    /// Get this node's previous named sibling.
    public func prevNamedSibling() -> Node? {
        Node(ts_node_prev_named_sibling(node))
    }
    
    /// Get the smallest node within this node that spans the given range.
    public func descendantForByteRange(start: uint, end: uint) -> Node? {
        Node(ts_node_descendant_for_byte_range(node, start, end))
    }

    /// Get the smallest named node within this node that spans the given range.
    public func namedDescendantForByteRange(start: uint, end: uint) -> Node? {
        Node(ts_node_named_descendant_for_byte_range(node, start, end))
    }
    
    /// Get the smallest node within this node that spans the given range.
    public func descendantForPointRange(start: TSPoint, end: TSPoint) -> Node? {
        Node(ts_node_descendant_for_point_range(node, start, end))
    }
    
    /// Get the smallest named node within this node that spans the given range.
    public func namedDescendantForPointRange(start: TSPoint, end: TSPoint) -> Node? {
        Node(ts_node_named_descendant_for_point_range(node, start, end))
    }
    
    public func toSexp() -> String {
        let cString = ts_node_string(node)
        let result = String(cString: cString!)
        cString?.deallocate()
        return result
    }

    /// Edit this node to keep it in-sync with source code that has been edited.
    ///
    /// This function is only rarely needed. When you edit a syntax tree with the
    /// [Tree::edit] method, all of the nodes that you retrieve from the tree
    /// afterward will already reflect the edit. You only need to use [Node::edit]
    /// when you have a specific [Node] instance that you want to keep and continue
    /// to use after an edit.
    public mutating func edit(_ edit: inout TSInputEdit) {
        ts_node_edit(
            withUnsafeMutablePointer(to: &node) { $0 },
            withUnsafePointer(to: &edit) { $0 }
        )
    }
}

extension Node: Equatable {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.node.id == rhs.node.id
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
