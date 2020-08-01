//
//  Tree.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import TreeSitter

public struct InputEdit {
    public var rawInputEdit: TSInputEdit

    public init(
        startByte: UInt32,
        oldEndByte: UInt32,
        newEndByte: UInt32,
        startPoint: Point,
        oldEndPoint: Point,
        newEndPoint: Point
    ) {
        self.rawInputEdit = TSInputEdit(
            start_byte: startByte,
            old_end_byte: oldEndByte,
            new_end_byte: newEndByte,
            start_point: startPoint.rawPoint,
            old_end_point: oldEndPoint.rawPoint,
            new_end_point: newEndPoint.rawPoint
        )
    }
}

public struct Point {
    public let rawPoint: TSPoint

    public init(row: UInt32, column: UInt32) {
        self.rawPoint = TSPoint(row: row, column: column)
    }
}

public class Tree {
    var tree: OpaquePointer
    
    public init(_ tree: OpaquePointer) {
        self.tree = tree
    }
    
    deinit {
        ts_tree_delete(tree)
    }
    
    /// Get the root node of the syntax tree.
    public func rootNode() -> Node {
        Node(ts_tree_root_node(tree))!
    }

    /// Get the language that was used to parse the syntax tree.
    public func language() -> Language {
        Language(ts_tree_language(tree)!)
    }
    
    /// Create a new [TreeCursor] starting from the root of the tree.
    public func walk() -> TreeCursor {
        self.rootNode().walk()
    }
    
    /// Edit the syntax tree to keep it in sync with source code that has been
    /// edited.
    ///
    /// You must describe the edit both in terms of byte offsets and in terms of
    /// row/column coordinates.
    public func edit(_ inputEdit: inout InputEdit) {
        ts_tree_edit(tree, &inputEdit.rawInputEdit)
    }
}
