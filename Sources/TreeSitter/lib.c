// The Tree-sitter library can be built by compiling this one source file.
//
// The following directories must be added to the include path:
//   - include

#define _POSIX_C_SOURCE 200112L

#include "src/get_changed_ranges.c"
#include "src/language.c"
#include "src/lexer.c"
#include "src/node.c"
#include "src/parser.c"
#include "src/query.c"
#include "src/stack.c"
#include "src/subtree.c"
#include "src/tree_cursor.c"
#include "src/tree.c"
