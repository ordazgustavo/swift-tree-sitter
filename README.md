# Swift TreeSitter

This Package provides Swift bindings to the [tree-sitter](https://github.com/tree-sitter/tree-sitter) parsing library.

### Basic Usage

First, create a parser:

```swift
import SwiftTreeSitter

let parser = Parser()
```

First, you'll need a Tree-sitter grammar for the language you want to parse. 
There are many [existing grammars](https://github.com/tree-sitter) .

```swift
let javascript = Language(tree_sitter_javascript())
let rust = Language(tree_sitter_rust())
let go = Language(tree_sitter_go())
```

Then you can assign them to the parser:

```swift
parser.setLanguage(javascript)
```

Now you can parse source code:

```swift
let sourceCode = "let x = 1; console.log(x);"
let tree = parser.parse(source: sourceCode)!
let rootNode = tree.rootNode

XCTAssertEqual(rootNode.kind, "program")
XCTAssertEqual(rootNode.startPosition.column, 0)
XCTAssertEqual(rootNode.endPosition.column, 26)
```

### Editing

Once you have a syntax tree, you can update it when your source code changes. 
Passing in the previous edited tree makes `parse` run much more quickly:

```swift
// Replace 'let' with 'const'
let newSourceCode = "const x = 1; console.log(x);"

tree.edit(InputEdit(
  startByte: 0,
  oldEndByte: 3,
  newEndByte: 5,
  startPosition: Point(row: 0, column: 0),
  oldEndPosition: Point(row: 0, column: 3),
  newEndPosition: Point(row: 0, column: 5)
))

let newTree = parser.parse(source: newSourceCode, oldTree: tree)
```

### Text Input

The source code to parse can be provided either either as a string, a slice, a vector, or as a 
function that returns a slice.

```swift
let lines = source.components(separatedBy: .newlines)

let tree = parser.parseWith { (offset, position) -> Substring.UTF8View in
  let row = Int(position.row)
  let col = Int(position.column)
  if row < lines.count {
    let line = lines[row].utf8
    if col < line.count {
      return line[line.index(line.startIndex, offsetBy: col)...]
    } else {
      return Substring("\n").utf8
    }
  } else {
    return Substring().utf8
  }
}
```

## Notice

⚠️ Please note that this is still a work in progress, PRs welcome!

## Installation

This package is available through Swift Package Manager

```swift
.package(url: "https://github.com/ordazgustavo/swift-tree-sitter", from: "0.0.3")
```
