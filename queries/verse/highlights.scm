(line_comment) @comment @spell
(block_comment) @comment @spell
(indent_comment) @comment @spell

; Literals
(string
  ["\"" "\""] @string)
(string_fragment) @string
(escape_sequence) @string.escape
(char) @string
(integer) @number
(float) @number
(logic_literal) @boolean
(path_literal) @namespace

(identifier) @variable
((identifier) @variable.builtin
  (#match? @variable.builtin "^(Self)$"))

(function_call
  function: (identifier) @function)
(of_expression
  lhs: (identifier) @function)

([
  (function_call
    function: (identifier) @keyword.import)
  (of_expression
    lhs: (identifier) @keyword.import)
] (#match? @keyword.import "^(import)$"))
([
  (function_call
    function: (identifier) @function.builtin)
  (of_expression
    lhs: (identifier) @function.builtin)
] (#match? @function.builtin "^(generator|subtype|castable_subtype)$"))

; Namespaces usage
(qualifier
  (identifier) @namespace)
(qualifier
  (identifier) @namespace.builtin
  (#match? @namespace.builtin "^(super|local)$"))

([
  (function_call
    function: (identifier) @_
    (_) @namespace)
  (of_expression
    lhs: (identifier) @_
    rhs: (_) @namespace)
] (#match? @_ "^(import)$"))

(macro_call
  macro: (identifier) @_
  (block
    (_) @namespace)
  (#match? @_ "^(using|scoped)$"))

(macro_call
  macro: (identifier) @function.macro)

; Field access
(field_expression
  field: (identifier) @variable.member)
(function_call
  function: (field_expression
    field: (identifier) @function))

; Declarations
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

; for (e:iterator)
(macro_call
  macro: (identifier) @_
  arguments: (argument_list
    (declaration
      type_hint: (identifier) @variable))
  (#match? @_ "^(for)$"))

; Archetype
([
  (macro_call
    macro: (identifier) @type
    (block))
  (macro_call
    macro: (identifier) @type
    (block
      (declaration
        lhs: (identifier) @property)))
] (#not-match? @type "^(module|struct|class|enum|interface|profile|using|map|array|logic|spawn|sync|race|rush|branch|defer|type|external|for|loop|while|do|if|else|case|then)$"))

(macro_call
  macro: (identifier)
  (block
    (comma_separated_group
      (declaration
        lhs: (identifier) @variable.member))))

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
  macro: (identifier) @keyword.import
  (#match? @keyword.import "^(using)$"))
(macro_call
  macro: (identifier) @keyword.macro
  (#match? @keyword.macro "^(profile|spawn|sync|race|rush|branch|defer|external)$"))
(macro_call
  macro: (identifier) @keyword.macro.type
  (#match? @keyword.macro.type "^(map|array|logic|type)$"))
(macro_call
  macro: (identifier) @keyword.type
  (#match? @keyword.type "^(module|struct|class|enum|interface)$"))

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
(function_declaration
  (unary_expression
    (declaration
      lhs: (identifier) @variable.parameter)))

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
  "->"
  ".."
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
  "to"
  "where"
] @keyword.operator

(unary_expression
  (_)
  .
  "?" @keyword.operator)

; Attributes
(at_attributes
  ["@"] @annotation.delimiter
  (identifier) @annotation)
(at_attributes
  ["@"] @annotation.delimiter
  (macro_call
    macro: (identifier) @annotation))

(attributes
  (identifier) @attribute)
(attributes
  (macro_call
    macro: (identifier) @attribute))
(attributes
  ["<" ">"] @attribute.delimiter)

([
  (attributes
    "<" @attribute.visibility.delimiter
    .
    (identifier) @attribute.visibility @_
    .
    ">" @attribute.visibility.delimiter)
  (attributes
    "<" @attribute.visibility.delimiter
    .
    (macro_call
      macro: (identifier) @attribute.visibility @_)
    .
    ">" @attribute.visibility.delimiter)
] (#match? @_ "^(internal|public|private|protected|scoped)$"))

