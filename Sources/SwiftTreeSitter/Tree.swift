//
//  Tree.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import TreeSitter

public class Tree {
    var tree: OpaquePointer
    
    public init(_ tree: OpaquePointer) {
        self.tree = tree
    }
    
    deinit {
        ts_tree_delete(tree)
    }
    
    /// Get the root node of the syntax tree.
    public var rootNode: Node {
        Node(ts_tree_root_node(tree))!
    }

    /// Get the language that was used to parse the syntax tree.
    public var language: Language {
        Language(ts_tree_language(tree)!)
    }
    
    /// Create a new `TreeCursor` starting from the root of the tree.
    public func walk() -> TreeCursor {
        rootNode.walk()
    }
    
    /// Edit the syntax tree to keep it in sync with source code that has been
    /// edited.
    ///
    /// You must describe the edit both in terms of byte offsets and in terms of
    /// row/column coordinates.
    public func edit(_ inputEdit: inout InputEdit) {
        ts_tree_edit(tree, &inputEdit.rawInputEdit)
    }
    
    /// Edit the syntax tree to keep it in sync with source code that has been
    /// edited.
    ///
    /// You must describe the edit both in terms of byte offsets and in terms of
    /// row/column coordinates.
    public func edit(_ inputEdit: @autoclosure () -> InputEdit) {
        var edit = inputEdit()
        ts_tree_edit(tree, &edit.rawInputEdit)
    }
    
    public func clone() -> Tree {
        Tree(ts_tree_copy(tree))
    }
    
    /// Compare this old edited syntax tree to a new syntax tree representing
    /// the same document, returning a sequence of ranges whose syntactic
    /// structure has changed.
    ///
    /// For this to work correctly, this syntax tree must have been edited such
    /// that its ranges match up to the new tree. Generally, you'll want to call
    /// this method right after calling one of the
    /// `Parser.parse(source:oldTree:)` functions. Call it on the old tree that
    /// was passed to parse, and pass the new tree that was returned from
    /// `parse`.
    public func changedRanges(other: Tree) -> [STSRange] {
        var count = CUnsignedInt(0)
        let ptr = ts_tree_get_changed_ranges(tree, other.tree, &count)
        
        return UnsafeBufferPointer(start: ptr, count: Int(count)).map {
            STSRange(
                startPoint: Point(raw: $0.start_point),
                endPoint: Point(raw: $0.end_point),
                startByte: $0.start_byte,
                endByte: $0.end_byte
            )
        }
    }
}
