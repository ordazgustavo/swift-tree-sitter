//
//  python.h
//  
//
//  Created by Gustavo Ordaz on 8/2/20.
//

#ifndef python_h
#define python_h

#include "parser.h"

#ifdef __cplusplus
extern "C" {
#endif

const TSLanguage *tree_sitter_python(void);

#ifdef __cplusplus
}
#endif

#endif /* python_h */
