//
//  File.swift
//  
//
//  Created by Gustavo Ordaz on 8/3/20.
//

import SwiftTreeSitter
import TreeSitterJavaScript

struct JavaScript {
    var parser = Language(tree_sitter_javascript())
}
