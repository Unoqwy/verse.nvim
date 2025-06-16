--- @class VerseNvim
--- @field config VerseNvimConfig?
local M = {}

--- @class VerseNvimConfig
---
--- Whether to exclusively register workspace folders that are packages in the .vproject file,
--- ignoring the default(s).
--- In practice, the LSP server ignores all other workspaces, so registering them is likely unwanted.
--- @field vproject_workspace_folders_only boolean
---
--- Whether to automatically delete ._ (AppleDouble) files when writing to a non-Mac
--- file system from a MacOS host. Those files confuse the Verse LSP server.
--- Only relevant on MacOS.
--- @field macos_auto_delete_annoying_files boolean

--- @type VerseNvimConfig
local config_defaults = {
  vproject_workspace_folders_only = true,
  macos_auto_delete_annoying_files = true,
}

--- @param opts VerseNvimConfig
function M.setup(opts)
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, config_defaults)
  M.config = opts

  if vim.fn.has("nvim-0.11") == 0 then
    return vim.notify("verse.nvim requires nvim >= 0.11. Please update Neovim.", vim.log.levels.WARN, { title = "verse.nvim" })
  end

  vim.lsp.enable("verse")

  local ok, ts_parsers = pcall(require, "nvim-treesitter.parsers")
  if ok then
    local parser_config = ts_parsers.get_parser_configs()
    parser_config.verse = {
      install_info = {
        url = "https://github.com/Unoqwy/tree-sitter-verse.git",
        files = { "src/parser.c", "src/scanner.c" },
      },
    }
  end

  if vim.uv.os_uname().sysname == "Darwin" and opts.macos_auto_delete_annoying_files ~= false then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "*.verse",
      callback = function()
        local file = vim.fn.expand("%:p")
        local annoying_macos_file = vim.fs.joinpath(vim.fs.dirname(file), "._" .. vim.fs.basename(file))
        vim.uv.fs_unlink(annoying_macos_file)
      end,
    })
  end
end

return M

