# verse.nvim

[Verse](https://dev.epicgames.com/documentation/en-us/fortnite/verse-language-reference) language support for Neovim.

## Features

- [x] Tree-sitter syntax highlighting ([tree-sitter-verse](https://github.com/Unoqwy/tree-sitter-verse))
- [x] Use the LSP server from the official VSCode extension (finds it locally)
- [x] Find and load .vproject from anywhere in a UEFN project
- [ ] Verse Workflow Server support
  * [x] Commands
  * [ ] Progress reporting
  * [ ] Build state
- [x] WSL support

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- plugins/verse.lua
return {
  "Unoqwy/verse.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  build = ":TSUpdate verse",
  opts = {},
}
```

For other plugin managers use an equivalent declaration, and make sure to call:

```lua
require("verse").setup()
```

## Usage

### Verse Workflow Server

- `:VerseBuild` - Build Verse Code
- `:VersePush` - Push Verse Changes
- `:VersePush all` - Push Changes

### Useful functions

```lua
-- list digest files which are usually not located alongside user code 
require("verse.project").list_digest_files()

-- variant to the above function that returns a `fd` command line to list digest files
require("verse.project").list_digest_files_cmd()
```

### fzf-lua example snippet

```lua
-- find digest files and pick one to open
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

