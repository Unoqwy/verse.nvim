; Scopes
(source_file) @local.scope
(indented_block) @local.scope
(braced_block) @local.scope
(block_indent) @local.scope
(if_expression) @local.scope
(for_expression) @local.scope
(loop_expression) @local.scope
(block_expression) @local.scope

; Imports
(using_statement
  (path_literal) @local.definition.import)
((call_expression
  function: (identifier) @_
  arguments: (argument_list
    (argument (path_literal) @local.definition.import)))
  (#match? @_ "^(import)$"))

; Function / constructor definitions. The signature can carry up to two trailing
; specifier layers plus one on the name; constructors written `:=` with an
; archetype body are assignment_expression with the call on the left.
(function_definition
  signature: [
    (call_expression
      function: [
        (identifier) @local.definition.function
        (decorated_expression operand: (identifier) @local.definition.function)
      ])
    (decorated_expression
      operand: (call_expression
        function: [
          (identifier) @local.definition.function
          (decorated_expression operand: (identifier) @local.definition.function)
        ]))
    (decorated_expression
      operand: (decorated_expression
        operand: (call_expression
          function: [
            (identifier) @local.definition.function
            (decorated_expression operand: (identifier) @local.definition.function)
          ])))
  ])
(assignment_expression
  left: [
    (call_expression
      function: [
        (identifier) @local.definition.function
        (decorated_expression operand: (identifier) @local.definition.function)
      ])
    (decorated_expression
      operand: (call_expression
        function: [
          (identifier) @local.definition.function
          (decorated_expression operand: (identifier) @local.definition.function)
        ]))
    (decorated_expression
      operand: (decorated_expression
        operand: (call_expression
          function: [
            (identifier) @local.definition.function
            (decorated_expression operand: (identifier) @local.definition.function)
          ])))
  ])

; Definitions (only direct children of a block scope, so named arguments
; and archetype fields are not treated as definitions)
([
  (source_file
    (assignment_expression
      left: (identifier) @local.definition.var))
  (indented_block
    (assignment_expression
      left: (identifier) @local.definition.var))
  (braced_block
    (assignment_expression
      left: (identifier) @local.definition.var))
  (block_indent
    (assignment_expression
      left: (identifier) @local.definition.var))
])
(var_definition
  name: (identifier) @local.definition.var)

; Type definitions: Name := class/struct/interface/enum/module { ... }
; (last, so type wins over the generic var definition above)
(assignment_expression
  left: (identifier) @local.definition.type
  right: [
    (class_expression)
    (struct_expression)
    (interface_expression)
    (enum_expression)
    (module_expression)
  ])

; Parameters and fields are intentionally omitted — they duplicate vars and
; clutter the buffer symbol list.

; References
(identifier) @local.reference
