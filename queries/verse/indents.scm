[
  (indented_block)          ; `head:` colon-introduced block
  (braced_block)            ; { ... }
  (archetype_instantiation) ; Type{ Field := ... }
  (map_literal)             ; map{ ... }
  (array_literal)           ; array{ ... }
  (option_literal)          ; option{ ... }
  (parenthesized_expression); ( ... ) spanning lines
  (argument_list)           ; call / subscript args spanning lines
] @indent.begin

; Attempt at getting indent blocks to open
(function_definition
  body: (block_indent)) @indent.begin (#set! indent.start_at_same_line 1)

[
  "}"
  ")"
  "]"
] @indent.branch @indent.end

[
  (line_comment)
  (block_comment)
  (string)
] @indent.auto
