# verse.nvim

[Verse](https://dev.epicgames.com/documentation/en-us/fortnite/verse-language-reference) language support for Neovim.

## Features

- [x] Tree-sitter syntax highlighting
- [x] Use the LSP server from the official VSCode extension (finds it locally)
- [x] Find and load .vproject from anywhere in a UEFN project
- [ ] Support for Verse Workflow Server

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- plugins/verse.lua
return {
    "Unoqwy/verse.nvim",
    opts = {},
}
```

Using another plugin manager:

```lua
require("verse").setup()
```

## Usage

You can use `require("verse.project").list_digest_files()` or `require("verse.project").list_digest_files_cmd()` to list the digest files which are usually not located alongside user code.

Example with fzf-lua:

```lua
vim.keymap.set("n", "<leader>od", function()
  local cmd = require("verse.project").list_digest_files_cmd()
  require("fzf-lua").fzf_exec(cmd, {
    prompt = "Digest Files > ",
    actions = {
      ["default"] = require("fzf-lua").actions.file_edit,
    }
  })
end)
```

