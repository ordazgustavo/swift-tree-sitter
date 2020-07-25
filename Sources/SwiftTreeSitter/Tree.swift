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
}
