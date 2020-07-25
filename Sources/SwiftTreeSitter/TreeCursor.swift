//
//  TreeCursor.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import TreeSitter

public struct TreeCursor {
    var cursor: TSTreeCursor
    
    public init(_ cursor: TSTreeCursor) {
        self.cursor = cursor
    }
    
    public init() {
        self.cursor = TSTreeCursor()
    }
    
    /// Get the tree cursor's current [Node].
    public func node() -> Node {
        Node(ts_tree_cursor_current_node(withUnsafePointer(to: cursor) { $0 }))!
    }

    /// Get the numerical field id of this tree cursor's current node.
    ///
    /// See also [field_name](TreeCursor::field_name).
    public func fieldId() -> TSFieldId? {
        let id = ts_tree_cursor_current_field_id(withUnsafePointer(to: cursor) { $0 })
        guard id == 0 else { return .none }
        
        return id
    }

    /// Get the field name of this tree cursor's current node.
    public func fieldName() -> String? {
        let ptr = ts_tree_cursor_current_field_name(withUnsafePointer(to: cursor) { $0 })
        guard let pointer = ptr else { return .none }
        return String(cString: pointer)
    }

    /// Move this cursor to the first child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns `false`
    /// if there were no children.
    @discardableResult
    public mutating func gotoFirstChild() -> Bool {
        ts_tree_cursor_goto_first_child(withUnsafeMutablePointer(to: &cursor) { $0 })
    }

    /// Move this cursor to the parent of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns `false`
    /// if there was no parent node (the cursor was already on the root node).
    public mutating func gotoParent() {
        ts_tree_cursor_goto_parent(withUnsafeMutablePointer(to: &cursor) { $0 })
    }
    
    /// Move this cursor to the next sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns `false`
    /// if there was no next sibling node.
    @discardableResult
    public mutating func gotoNextSibling() -> Bool {
        ts_tree_cursor_goto_next_sibling(withUnsafeMutablePointer(to: &cursor) { $0 })
    }
    
    /// Move this cursor to the first child of its current node that extends beyond
    /// the given byte offset.
    ///
    /// This returns the index of the child node if one was found, and returns `None`
    /// if no such child was found.
    public mutating func gotoFirstChildForByte(index: uint) -> uint? {
        let result = ts_tree_cursor_goto_first_child_for_byte(
            withUnsafeMutablePointer(to: &cursor) { $0 },
            index
        )
        guard result < 0 else { return .none }
        
        return uint(result)
    }

    /// Re-initialize this tree cursor to start at a different node.
    public mutating func reset(node: Node) {
        ts_tree_cursor_reset(withUnsafeMutablePointer(to: &cursor) { $0 }, node.node)
    }
}
