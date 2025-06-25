(comment) @comment @spell

; Literals
(string
  ["\"" "\""] @string)
(string_fragment) @string
(char) @string
(integer) @number
(float) @number
(logic_literal) @keyword
(path_literal) @module

(identifier) @variable
((identifier) @variable.builtin
  (#match? @variable.builtin "^(Self)$"))

(function_call
  function: (identifier) @function)
(of_expression
  lhs: (identifier) @function)

([
  (function_call
    function: (identifier) @keyword)
  (of_expression
    lhs: (identifier) @keyword)
] (#match? @keyword "^(import)$"))

(field_expression
  field: (identifier) @variable.member)
(function_call
  function: (field_expression
    field: (identifier) @function))

(declaration
  lhs: "("*
  lhs: (identifier) @constant)
(declaration
  (var_keyword) @keyword
  lhs: "("*
  lhs: (identifier) @variable)
(set_expression
  lhs: (identifier) @variable)

(named_argument
  name: (identifier) @variable.parameter)

; Type references
(unary_expression
  operator: "?"
  operand: (identifier) @type)
(map_container
  key: (identifier) @type)
(map_container
  value: (identifier) @type)
(array_container
  value: (identifier) @type)
(function_declaration
  ret_type: (identifier) @type)
(declaration
  type_hint: (identifier) @type)

([
  (unary_expression
    operator: "?"
    operand: (identifier) @type.builtin)
  (map_container
    key: (identifier) @type.builtin)
  (map_container
    value: (identifier) @type.builtin)
  (array_container
    value: (identifier) @type.builtin)
  (function_declaration
    ret_type: (identifier) @type.builtin)
  (declaration
    type_hint: (identifier) @type.builtin)
] (#match? @type.builtin "^(void|string|char|char32|int|rational|float|logic|any)$"))

; Archetype
(macro_call
  macro: (identifier) @type
  (block
    (declaration)*))
(macro_call
  macro: (identifier)
  (block
    (declaration
      lhs: (identifier) @variable.member)))

; Builtin macros
([
  (declaration
    lhs: "("*
    lhs: (identifier) @type
    rhs: (macro_call
      macro: (identifier) @_))
  (declaration
    rhs: (macro_call
      macro: (identifier) @_
      arguments: (argument_list
        (identifier) @type)))
] (#match? @_ "^(struct|class|enum|interface)$"))

(declaration
  lhs: "("*
  lhs: (identifier) @module
  rhs: (macro_call
    macro: (identifier) @_)
  (#match? @_ "^(module)$"))

(macro_call
  macro: (identifier) @function.macro)

(macro_call
  macro: (identifier) @keyword
  (#match? @keyword "^(module|struct|class|enum|interface|profile|using|map|array|logic|spawn|sync|race|rush|branch|defer|type|external)$"))

(macro_call
  macro: (identifier) @keyword.conditional
  (#match? @keyword.conditional "^(if|else|case|then)$"))
(else_keyword) @keyword.conditional

(macro_call
  macro: (identifier) @keyword.repeat
  (#match? @keyword.repeat "^(for|loop|while|do)$"))

; Function declaration
(function_declaration
  name: (_) @function)
(function_declaration
  (declaration
    lhs: (identifier) @variable.parameter))

; Attributes
(at_attributes
  ["@"] @attribute
  (identifier) @attribute)
(at_attributes
  ["@"] @attribute
  (macro_call
    macro: (identifier) @attribute))

(attributes
  (identifier) @attribute)
(attributes
  (macro_call
    macro: (identifier) @attribute))

; Tokens
[
 "{"
 "}"
 "("
 ")"
 "["
 "]"
 ":)"
] @punctuation.bracket

[
 ";"
 ","
 "."
 ". "
] @punctuation.delimiter

[
  "*"
  "/"
  "+"
  "-"
  "="
  "<>"
  "<"
  ">"
  "<="
  ">="
  "?"
  ":"
  "macro:"
  ":="
  "=>"
] @operator

[
  "set"
  "return"
  (continue_expression)
  (break_expression)
] @keyword

[
  "and"
  "or"
  "not"
  "of"
] @keyword.operator

(attributes
  ["<" ">"] @attribute)

