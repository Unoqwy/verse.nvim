# verse.nvim

[Verse](https://dev.epicgames.com/documentation/en-us/fortnite/verse-language-reference) language support for Neovim.

## Features

- [x] Tree-sitter syntax highlighting ([tree-sitter-verse](https://github.com/Unoqwy/tree-sitter-verse))
- [x] Use the LSP server from the official VSCode extension (finds it locally)
- [x] Directly open any file within a UEFN project (finds .vproject to resolve workspace folders automatically)
- [x] Verse Workflow Server support
  * [x] Commands
  * [x] Build/Push progress
- [x] WSL support
- [x] CrossOver support (macOS)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- plugins/verse.lua
return {
  "Unoqwy/verse.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    -- "j-hui/fidget.nvim", -- Uncomment to get Build/Push spinning progress
  },
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

### Temporary Workaround

- `:FixVerse` - Fix `external{} macro expected here` bug without needing to Build Verse.  
                This command will be removed once the the error stops happening.

### Useful functions

```lua
-- list digest files which are usually not located alongside user code 
require("verse.project").list_digest_files()

-- variant to the above function that returns a `fd` (or `fdfind`) command line to list digest files
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

## fidget.nvim integration

If present, this plugin will use [fidget.nvim](https://github.com/j-hui/fidget.nvim) to display Build/Push progress.  
The integration is loaded only once the workflow server connects for the first time.

## WSL Additional Information

Make sure WSL uses [Mirrored mode networking](https://learn.microsoft.com/en-us/windows/wsl/networking#mirrored-mode-networking) for the plugin to connect to the Workflow Server running on the Windows host properly.

Recommendation for performance:

```powershell
# within an elevated (Run as administrator) PowerShell:
Add-MpPreference -ExclusionPath "C:\Users\$env:USERNAME\AppData\Local\UnrealEditorFortnite\Saved\VerseProject"
```

