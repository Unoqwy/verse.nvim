local M = {}

--- @class verse.Config
---
--- Whether to exclusively register workspace folders that are packages in the .vproject file,
--- ignoring the default(s).
--- In practice, the LSP server ignores all other workspaces, so registering them is likely unwanted.
--- @field vproject_workspace_folders_only? boolean
--- Whether to automatically delete ._ (AppleDouble) files when writing to a non-Mac
--- file system from a MacOS host. Those files confuse the Verse LSP server.
--- Only relevant on MacOS.
--- @field macos_auto_delete_annoying_files? boolean
--- Verse Workflow Server related options.
--- @field workflow_server? verse.WorkflowServerConfig
--- Enable debug mode used for this plugin's development.
--- @field debug? boolean
--- Integrations related options.
--- @field integrations? verse.IntegrationsConfig

--- @class verse.WorkflowServerConfig
---
--- Default address of the workflow server.
--- @field default_address? string
--- Default port of the workflow server.
--- @field default_port? integer
--- Whether to automatically attempt to connect to the server when calling
--- an action that requires an active connection.
--- @field auto_connect? boolean

--- @class verse.IntegrationsConfig
---
--- Whether to use fidget.nvim to display spinning progress from the Workflow Server.
--- @field fidget_nvim? boolean

--- @type verse.Config
local config_defaults = {
  vproject_workspace_folders_only = true,
  macos_auto_delete_annoying_files = true,
  workflow_server = {
    default_address = "127.0.0.1",
    default_port = 1962,
    auto_connect = true,
  },
  debug = false,
  integrations = {
    fidget_nvim = true
  }
}

--- Gets the current plugin config.
--- @return verse.Config
function M.get_config()
  return M._config or config_defaults
end

--- @return boolean
function M.debug_enabled()
  return M._config.debug or false
end

--- @param config? verse.Config
function M.setup(config)
  config = config or {}
  config = vim.tbl_deep_extend("keep", config, config_defaults)
  M._config = config

  if vim.fn.has("nvim-0.11") == 0 then
    return vim.notify("verse.nvim requires nvim >= 0.11. Please update Neovim.",
      vim.log.levels.WARN, { title = "verse.nvim" })
  end

  vim.lsp.enable("verse")

  local ok, ts_parsers = pcall(require, "nvim-treesitter.parsers")
  if ok then
    local parser_config = ts_parsers.get_parser_configs()
    parser_config["verse"] = {
      install_info = {
        url = "https://github.com/Unoqwy/tree-sitter-verse.git",
        files = { "src/parser.c", "src/scanner.c" },
      },
    }
  end

  M.register_commands()

  if vim.uv.os_uname().sysname == "Darwin" and config.macos_auto_delete_annoying_files then
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

function M.register_commands()
  vim.api.nvim_create_user_command("VerseConnect", function()
    require("verse.workflow_server").connect()
  end, {
    nargs = 0,
    desc = "Connect to the Verse Workflow Server",
  })

  vim.api.nvim_create_user_command("VerseDisconnect", function()
    require("verse.workflow_server").disconnect()
  end, {
    nargs = 0,
    desc = "Disconnect from the Verse Workflow Server",
  })

  vim.api.nvim_create_user_command("VerseBuild", function()
    require("verse.workflow_server").build()
  end, {
    nargs = 0,
    desc = "Build Verse code for the current workspace",
  })

  vim.api.nvim_create_user_command("VersePush", function(opts)
    local arg = (#opts.args > 0 and opts.args) or "verse"
    if arg ~= "all" and arg ~= "verse" then
      error("Invalid argument: " .. arg .. ". Expected 'all' or 'verse'")
      return
    end
    require("verse.workflow_server").push_changes({
      verse_only = arg == "verse",
    })
  end, {
    nargs = "?",
    desc = "Request to Push (Verse) Changes",
    complete = function()
      return { "all", "verse" }
    end,
  })
end

local integration_done = false

function M._init_workflow_integration()
  if integration_done then
    return
  end
  integration_done = true

  local config = M.get_config()
  if config.integrations.fidget_nvim then
    -- checking fidget.progress to exclude legacy branch
    local fidget_nvim_present, _ = pcall(require, "fidget.progress")
    if fidget_nvim_present then
      require("verse.integration.fidget_nvim").init()
    end
  end
end

--- @param title string
--- @return fun(msg:string, level?:integer)
function M.create_notifier(title)
  return function(msg, level)
    vim.notify(msg, level, {
      title = title,
    })
  end
end

return M
