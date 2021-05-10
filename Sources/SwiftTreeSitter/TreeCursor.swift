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
        ts_tree_cursor_delete(&cursor)
    }
    
    /// Get the tree cursor's current `Node`.
    public var node: Node {
        Node(ts_tree_cursor_current_node(&cursor))!
    }

    /// Get the numerical field id of this tree cursor's current node.
    ///
    /// See also `fieldName`.
    public func fieldId() -> UInt16? {
        let id = ts_tree_cursor_current_field_id(&cursor)
        
        if id == 0 {
            return nil
        }
        
        return id
    }

    /// Get the field name of this tree cursor's current node.
    public func fieldName() -> String? {
        guard let name = ts_tree_cursor_current_field_name(&cursor) else {
            return nil
        }
        
        return String(cString: name)
    }

    /// Move this cursor to the first child of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns
    /// `false` if there were no children.
    @discardableResult
    public func gotoFirstChild() -> Bool {
        ts_tree_cursor_goto_first_child(&cursor)
    }

    /// Move this cursor to the parent of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns
    /// `false` if there was no parent node (the cursor was already on the root
    /// node).
    public func gotoParent() -> Bool {
        ts_tree_cursor_goto_parent(&cursor)
    }
    
    /// Move this cursor to the next sibling of its current node.
    ///
    /// This returns `true` if the cursor successfully moved, and returns
    /// `false` if there was no next sibling node.
    @discardableResult
    public func gotoNextSibling() -> Bool {
        ts_tree_cursor_goto_next_sibling(&cursor)
    }
    
    /// Move this cursor to the first child of its current node that extends beyond
    /// the given byte offset.
    ///
    /// This returns the index of the child node if one was found, and returns
    /// `nil` if no such child was found.
    public func gotoFirstChildForByte(index: UInt) -> Int64? {
        let result = ts_tree_cursor_goto_first_child_for_byte(&cursor, CUnsignedInt(index))
            
        if result < 0 {
            return nil
        }
        
        return result
    }

    /// Re-initialize this tree cursor to start at a different node.
    public func reset(node: Node) {
        ts_tree_cursor_reset(&cursor, node.node)
    }
}
