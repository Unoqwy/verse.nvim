local M = {}

function M.setup(opts)
  if vim.fn.has("nvim-0.11") == 0 then
    return vim.notify("verse.nvim requires nvim >= 0.11. Please update neovim.", vim.log.levels.WARN, { title = "verse.nvim" })
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

end

return M
