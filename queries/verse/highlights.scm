; Comments
(line_comment) @comment @spell
(block_comment) @comment @spell

; Operators
[
  ":="
  "+="
  "-="
  "*="
  "/="
  "="
  "<>"
  "<"
  "<="
  ">"
  ">="
  "+"
  "-"
  "*"
  "/"
  "&"
  "|"
  ".."
  "->"
  "=>"
  "?"
  "^"
] @operator

; Punctuation
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," ";" "." ":"] @punctuation.delimiter

; Literals
(string) @string
(escape_sequence) @string.escape
(interpolation
  ["{" "}"] @punctuation.special)
(char_literal) @string
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean
(path_literal) @namespace

; Identifiers
(identifier) @variable
((identifier) @variable.builtin
  (#match? @variable.builtin "^(Self)$"))

; Field access (before function calls so method calls win)
(member_expression
  member: (identifier) @variable.member)

; Function calls
(call_expression
  function: [
    (identifier) @function.call
    (member_expression
      member: (identifier) @function.call)
    (decorated_expression
      operand: [
        (identifier) @function.call
        (member_expression
          member: (identifier) @function.call)
      ])
  ])

; Imports
(using_statement
  "using" @keyword.import)
(using_statement
  (identifier) @namespace)
((call_expression
  function: (identifier) @keyword.import)
  (#match? @keyword.import "^(import)$"))
((call_expression
  function: (identifier) @keyword.import
  arguments: (argument_list
    (argument [(string) (path_literal)] @namespace)))
  (#match? @keyword.import "^(import)$"))

; Builtin functions
((call_expression
  function: (identifier) @function.builtin)
  (#match? @function.builtin "^(generator|subtype|castable_subtype|tuple|weak_map)$"))

; Namespaces / qualified access ((path:)Name, (super:)Name, (local:)Name)
(qualified_access
  qualifier: (parenthesized_expression
    (type_annotation
      value: (identifier) @namespace)))
((qualified_access
  qualifier: (parenthesized_expression
    (type_annotation
      value: (identifier) @namespace.builtin)))
  (#match? @namespace.builtin "^(super|local)$"))

; Macros
(macro_block
  head: (identifier) @function.macro)

((macro_block
  head: (identifier) @keyword.macro)
  (#match? @keyword.macro "^(race|rush|profile|external)$"))
((macro_block
  head: (call_expression
    function: (identifier) @keyword.macro))
  (#match? @keyword.macro "^(race|rush|profile|external)$"))
((macro_block
  head: (call_expression
    function: (identifier) @keyword.repeat))
  (#match? @keyword.repeat "^(while)$"))

; Named arguments: Foo(Name := value)
(argument_list
  (argument
    (assignment_expression
      left: (identifier) @variable.parameter)))

; Definition names (X := value). Only direct children of a block scope, so
; named arguments and archetype fields are excluded
([
  (source_file
    (assignment_expression
      left: (identifier) @constant))
  (indented_block
    (assignment_expression
      left: (identifier) @constant))
  (braced_block
    (assignment_expression
      left: (identifier) @constant))
  (block_indent
    (assignment_expression
      left: (identifier) @constant))
])

; Type keywords
(class_expression "class" @keyword.type)
(struct_expression "struct" @keyword.type)
(interface_expression "interface" @keyword.type)
(enum_expression "enum" @keyword.type)
(module_expression "module" @keyword.type)

; Type definition names
(assignment_expression
  left: (identifier) @type
  right: [
    (class_expression)
    (struct_expression)
    (interface_expression)
    (enum_expression)
  ])
(assignment_expression
  left: (identifier) @module
  right: (module_expression))

; Enum members
(enum_expression
  (braced_block
    (identifier) @constant))

; Archetypes
(archetype_instantiation
  type: (identifier) @type)
(archetype_instantiation
  (assignment_expression
    left: (identifier) @property))
((archetype_instantiation
  type: (identifier) @keyword.macro)
  (#match? @keyword.macro "^(external)$"))

; Type references (annotations, var/return types, type constructors, supertypes)
([
  (type_annotation type: (identifier) @type)
  (var_definition type: (identifier) @type)
  (function_definition return_type: (identifier) @type)
  (optional_type (identifier) @type)
  (array_type (identifier) @type)
  (map_type (identifier) @type)
  (type_prefix (identifier) @type)
  (supertype_clause (identifier) @type)
])

; Builtin types
([
  (type_annotation type: (identifier) @type.builtin)
  (var_definition type: (identifier) @type.builtin)
  (function_definition return_type: (identifier) @type.builtin)
  (optional_type (identifier) @type.builtin)
  (array_type (identifier) @type.builtin)
  (map_type (identifier) @type.builtin)
  (type_prefix (identifier) @type.builtin)
  (supertype_clause (identifier) @type.builtin)
] (#match? @type.builtin "^(void|string|char|char32|int|rational|float|logic|any|comparable|type)$"))

; Function / constructor definition names. Handles F(), F<spec>(), F()<effect>, F<spec>()<effect>
(function_definition
  signature: [
    (call_expression
      function: [
        (identifier) @function.definition
        (decorated_expression operand: (identifier) @function.definition)
      ])
    (decorated_expression
      operand: (call_expression
        function: [
          (identifier) @function.definition
          (decorated_expression operand: (identifier) @function.definition)
        ]))
  ])
(assignment_expression
  left: [
    (call_expression
      function: [
        (identifier) @function.definition
        (decorated_expression operand: (identifier) @function.definition)
      ])
    (decorated_expression
      operand: (call_expression
        function: [
          (identifier) @function.definition
          (decorated_expression operand: (identifier) @function.definition)
        ]))
  ])

; Function parameters: typed arguments only appear in parameter lists
(argument
  (type_annotation
    value: (identifier) @variable.parameter))

; Operator-named functions (e.g. operator'+')
(function_definition
  signature: (call_expression
    function: (identifier) @constructor.builtin)
  (#match? @constructor.builtin "^_+$"))

; Definitions
(var_definition
  "var" @keyword)
(var_definition
  name: (identifier) @variable)
(set_expression
  "set" @keyword)
(set_expression
  target: (identifier) @variable)
(ref_expression
  "ref" @keyword)
(var_definition
  "live" @keyword)
(live_binding
  "live" @keyword)

; Control flow keywords
(if_expression
  ["if" "then" "else"] @keyword.conditional)
(case_expression "case" @keyword.conditional)
(for_expression
  ["for" "do"] @keyword.repeat)
(loop_expression "loop" @keyword.repeat)
(block_expression "block" @keyword)
(return_expression "return" @keyword)
(break_expression) @keyword
(continue_expression) @keyword
(yield_expression "yield" @keyword)
(spawn_expression "spawn" @keyword.macro)
(sync_expression "sync" @keyword.macro)
(branch_expression "branch" @keyword.macro)
(defer_expression "defer" @keyword.macro)

; Container keywords
(array_literal "array" @keyword.macro.type)
(map_literal "map" @keyword.macro.type)
(option_literal "option" @keyword.macro.type)
(tuple_expression "tuple" @keyword.macro.type)

; Word operators
(binary_expression
  ["and" "or" "where" "when" "over" "of" "is" "in" "to"] @keyword.operator)
(binary_expression
  "while" @keyword.repeat)
(unary_expression
  "not" @keyword.operator)
(postfix_query "?" @keyword.operator)

; Function calls for `of` keyword
(binary_expression
  left: [
    (identifier) @function.call
    (member_expression
      member: (identifier) @function.call)
  ]
  .
  "of")

; Attributes/specifiers
(specifier
  ["<" ">"] @attribute.delimiter)
(specifier
  name: (identifier) @attribute)

; Visibility specifiers highlight the whole <...> (brackets included)
((specifier
  "<" @attribute.visibility.delimiter
  name: (identifier) @attribute.visibility
  ">" @attribute.visibility.delimiter)
  (#match? @attribute.visibility "^(internal|public|private|protected|scoped)$"))

; Annotations (@-form)
(annotation
  "@" @annotation.delimiter)
(annotation
  name: (identifier) @annotation)
