//
//  TreeCursor.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import TreeSitter

public class TreeCursor {
    var cursor: TSTreeCursor
    
    init(_ cursor: TSTreeCursor) {
        self.cursor = cursor
    }
    
    public init() {
        self.cursor = TSTreeCursor()
    }
    
    deinit {
        withUnsafeMutablePointer(to: &cursor) { ts_tree_cursor_delete($0) }
    }
    
    /// Get the tree cursor's current [Node].
    public func node() -> Node {
        withUnsafePointer(to: cursor) {
            Node(ts_tree_cursor_current_node($0))!
        }
    }

    /// Get the numerical field id of this tree cursor's current node.
    ///
    /// See also `fieldName`.
    public func fieldId() -> TSFieldId? {
        let id = withUnsafePointer(to: cursor) {
            ts_tree_cursor_current_field_id($0)
        }
        
        if id == 0 {
            return nil
        }
        
        return id
    }

    /// Get the field name of this tree cursor's current node.
    public func fieldName() -> String? {
        let ptr = withUnsafePointer(to: cursor) {
            ts_tree_cursor_current_field_name($0)
        }
        
        guard let pointer = ptr else { return nil }
        
        return String(cString: pointer)
    }

    /// Move this cursor to the first child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns `false`
    /// if there were no children.
    @discardableResult
    public func gotoFirstChild() -> Bool {
        withUnsafeMutablePointer(to: &cursor) {
            ts_tree_cursor_goto_first_child($0)
        }
    }

    /// Move this cursor to the parent of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns `false`
    /// if there was no parent node (the cursor was already on the root node).
    public func gotoParent() -> Bool {
        withUnsafeMutablePointer(to: &cursor) { ts_tree_cursor_goto_parent($0) }
    }
    
    /// Move this cursor to the next sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns `false`
    /// if there was no next sibling node.
    @discardableResult
    public func gotoNextSibling() -> Bool {
        withUnsafeMutablePointer(to: &cursor) {
            ts_tree_cursor_goto_next_sibling($0)
        }
    }
    
    /// Move this cursor to the first child of its current node that extends beyond
    /// the given byte offset.
    ///
    /// This returns the index of the child node if one was found, and returns `None`
    /// if no such child was found.
    public func gotoFirstChildForByte(index: UInt32) -> Int64? {
        let result = withUnsafeMutablePointer(to: &cursor) {
            ts_tree_cursor_goto_first_child_for_byte($0, index)
        }
            
        if result < 0 {
            return nil
        }
        
        return result
    }

    /// Re-initialize this tree cursor to start at a different node.
    public func reset(node: Node) {
        withUnsafeMutablePointer(to: &cursor) {
            ts_tree_cursor_reset($0, node.node)
        }
    }
}
