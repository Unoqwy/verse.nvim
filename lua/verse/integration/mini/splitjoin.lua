--- Hooks to support splitting and joining Verse lines that
--- don't need commas at the end of line to separate expressions.
---
--- It improves mini.splitjoin for Verse editing but still has many flaws.
--- Better split behavior would require tree-sitter, which is out of scope for mini.splitjoin.
---
--- # Example usage
---
--- The recommended usage is to create a secondary toggle keybind,
--- considering not all expressions can work with their commas stripped.
---
--- ```lua
--- local verse_splitjoin = require("verse.integration.mini.splitjoin")
--- vim.keymap.set("n", "<leader>v,", function()
---   require("mini.splitjoin").toggle({
---     split = {
---       hooks_post = { verse_splitjoin.split_hooks_post(",") },
---     },
---     join = {
---       hooks_post = { verse_splitjoin.join_hooks_post(",") },
---     },
---   })
--- end)
--- ```
local M = {}

--- Hook to add missing commas between each joined expression, only in verse filetype.
--- @param separator string|nil Separator to use. Defaults to ';'
function M.join_hooks_post(separator)
  separator = separator or ","
  if #separator > 1 then
    separator = separator:sub(1, 1)
  end

  return function(join_positions)
    if vim.bo.filetype ~= "verse" then
      return
    end

    for i, join_pos in ipairs(join_positions) do
      if i == 1 or i == #join_positions then
        goto continue
      end

      local line_text = vim.fn.getline(join_pos.line)
      local segment_text = line_text:sub(1, join_pos.col)
      if segment_text:match("[" .. vim.pesc(",({[:") .. "]%s*$") then
        goto continue
      end

      local post_text = line_text:sub(join_pos.col + 1, -1)
      if post_text:match("^%s*[" .. vim.pesc(",)}]") .. "]") then
        goto continue
      end

      local line = join_pos.line - 1
      local ok = pcall(
        vim.api.nvim_buf_set_text, 0,
        line, join_pos.col,
        line, join_pos.col,
        { separator }
      )
      if not ok then
        goto continue
      end

      for _, alter_pos in ipairs(join_positions) do
        if alter_pos.col >= join_pos.col then
          alter_pos.col = alter_pos.col + 1
        end
      end

      ::continue::
    end

    return join_positions
  end
end

--- Hook to remove trailing commas on each split line, only in verse filetype.
---
--- It isn't recommend to have this as your default split behavior, as it may
--- break certain expressions. You likely want a separate keybind.
---
--- @param separator string|nil Separator to use. Defaults to ','
function M.split_hooks_post(separator)
  separator = separator or ","
  if #separator > 1 then
    separator = separator:sub(1, 1)
  end

  return function(join_positions)
    if vim.bo.filetype ~= "verse" then
      return
    end

    for _, join_pos in ipairs(join_positions) do
      local line_text = vim.fn.getline(join_pos.line)
      local found_col = line_text:find(separator .. "%s*$")
      if found_col == nil then
        goto continue
      end

      local line = join_pos.line - 1
      local ok = pcall(
        vim.api.nvim_buf_set_text,
        0,
        line,
        found_col - 1,
        line,
        found_col,
        {}
      )
      if not ok then
        goto continue
      end

      join_pos.col = join_pos.col - 1

      ::continue::
    end

    return join_positions
  end
end

return M
