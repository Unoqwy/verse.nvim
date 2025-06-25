(source_file) @local.scope
(block) @local.scope

; Imports
(macro_call
  macro: (identifier) @_
  (block
    (_) @local.definition.import)
  (#match? @_ "^(using)$"))
([
  (function_call
    function: (identifier) @_
    (_) @local.definition.import)
  (of_expression
    lhs: (identifier) @_
    rhs: (_) @local.definition.import)
] (#match? @_ "^(import)$"))

; Definitions
(declaration
  lhs: "("*
  lhs: (identifier) @local.definition.var)
(function_declaration
  name: (identifier) @local.definition.function)

; Not including parameter and fields for now as they become duplicates of var
; and that's not a good experience when browsing buffer symbols.
; Maybe a better solution in tree-sitter-verse could be found.
;
; (function_declaration
;   (declaration
;     lhs: (identifier) @local.definition.parameter))
;
; (macro_call
;   macro: (identifier)
;   (block
;     (declaration
;       lhs: (identifier) @local.definition.field)))

([
  (declaration
    lhs: "("*
    lhs: (identifier) @local.definition.type
    rhs: (macro_call
      macro: (identifier) @_))
  (declaration
    rhs: (macro_call
      macro: (identifier) @_
      arguments: (argument_list
        (identifier) @local.definition.type)))
] (#match? @_ "^(struct|class|enum|interface)$"))

; References
(identifier) @local.reference

