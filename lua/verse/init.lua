local M = {}

--- @class verse.Config
--- Whether to setup tree-sitter-verse. Set to false if you set it up manually.
--- @field treesitter? boolean
--- Path to a custom Verse LSP binary (use array to pass args). If nil, will attempt to be found automatically.
--- Prefer this setting over a custom lsp config to benefit from workspace folders and compatibility features.
--- @field lsp_binary? string|string[]
--- Options to connect to the LSP server in TCP mode (useful for debugging the server).
--- @field lsp_tcp_mode? verse.LspTcpMode
--- Verse.vsix extract options.
--- @field uefn_extract? verse.UefnExtractConfig
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

--- @class verse.LspTcpMode
--- Whether to use TCP to connect to the LSP server.
--- @field enabled? boolean
--- LSP server address.
--- @field address? string
--- LSP server port.
--- @field port? integer

--- @class verse.UefnExtractConfig
--- Whether to automatically extract the LSP server from the Verse.vsix shipped with UEFN.
--- Version checks ensure it's extracted again after updates.
--- @field enabled? boolean
--- Override path to Verse.vsix file. Set if the plugin fails to infer your UEFN installation directory.
--- @field vsix_path? string

--- @class verse.WorkflowServerConfig
--- Default address of the workflow server.
--- @field default_address? string
--- Default port of the workflow server.
--- @field default_port? integer
--- Whether to automatically attempt to connect to the server when calling
--- an action that requires an active connection.
--- @field auto_connect? boolean

--- @class verse.IntegrationsConfig
--- Whether to use fidget.nvim to display spinning progress from the Workflow Server.
--- @field fidget_nvim? boolean

--- @type verse.Config
local config_defaults = {
  treesitter = true,
  lsp_binary = nil,
  lsp_tcp_mode = {
    enabled = false,
    address = "127.0.0.1",
    port = 9010,
  },
  uefn_extract = {
    enabled = true,
    vsix_path = nil,
  },
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

--- Returns the current plugin config.
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

  if config.treesitter == true then
    M._setup_treesitter()
  end

  M._register_commands()

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

function M._setup_treesitter()
  local ok, ts_parsers = pcall(require, "nvim-treesitter.parsers")
  if ok then
    local parser_config = ts_parsers.get_parser_configs()
    if parser_config["verse"] ~= nil then
      return
    end
    parser_config["verse"] = {
      install_info = {
        url = "https://github.com/Unoqwy/tree-sitter-verse.git",
        files = { "src/parser.c", "src/scanner.c" },
        revision = "740426c641640b4c97b9b01753d58f9753356803",
      },
    }
  end
end

function M._register_commands()
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

  vim.api.nvim_create_user_command("FixVerse", function()
    M._temp_fix_verse()
  end, {
    nargs = 0,
    desc = "Temporary command to fix 'external{} macro expected here' bug without building Verse code",
  })

  vim.api.nvim_create_user_command("VerseRestart", function()
    local verse_lsp_clients = vim.lsp.get_clients({
      bufnr = nil,
      name = "verse",
    })
    for _, client in ipairs(verse_lsp_clients) do
      client:stop(true)
    end
    vim.lsp.enable("verse", false)

    local timer = assert(vim.uv.new_timer())
    timer:start(500, 0, function()
      timer:stop()
      timer:close()
      vim.schedule(function()
        vim.lsp.enable("verse", true)
      end)
    end)
  end, {
    nargs = 0,
    desc = "(Re)starts the Verse language server",
  })
  vim.api.nvim_create_user_command("VerseStop", function()
    local verse_lsp_clients = vim.lsp.get_clients({
      bufnr = nil,
      name = "verse",
    })
    for _, client in ipairs(verse_lsp_clients) do
      client:stop(true)
    end
    vim.lsp.enable("verse", false)
  end, {
    nargs = 0,
    desc = "Stops the Verse language server",
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
    if level <= vim.log.levels.DEBUG and not M.debug_enabled() then
      return
    end
    vim.notify(msg, level, {
      title = title,
    })
  end
end

function M._temp_fix_verse()
  local vproject_file = require("verse.project").find_vproject_file()
  if vproject_file == nil then
    vim.notify("Couldn't find the .vproject file to apply workaround fix to",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return
  end
  local file_contents = table.concat(vim.fn.readfile(vproject_file), "\n")
  local ok, json = pcall(vim.json.decode, file_contents)
  if not ok then
    vim.notify("Couldn't parse .vproject file",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return
  end

  local applied_fix = false
  local packages = json["packages"]
  if packages ~= nil then
    for _, package in ipairs(packages) do
      local desc = package["desc"]
      if desc ~= nil then
        local dir_path = desc["dirPath"]
        if dir_path:match("Content$") then
          local settings = desc["settings"]
          if settings ~= nil then
            settings["role"] = "Source"
            applied_fix = true
          end
        end
      end
    end
  end

  if not applied_fix then
    vim.notify("No fix applied. Unexpected .vproject format",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return
  end

  local new_file_contents = vim.json.encode(json)
  local fd = vim.uv.fs_open(vproject_file, "w", tonumber("644", 8))
  if fd ~= nil then
    vim.uv.fs_write(fd, new_file_contents, -1)
    vim.uv.fs_close(fd)
    print("Verse fix applied. LSP server will restart")

    local verse_lsp_clients = vim.lsp.get_clients({
      bufnr = nil,
      name = "verse",
    })
    for _, client in ipairs(verse_lsp_clients) do
      client:stop(true)
    end
    vim.lsp.enable("verse", false)

    local timer = assert(vim.uv.new_timer())
    timer:start(500, 0, function()
      timer:stop()
      timer:close()
      vim.schedule(function()
        vim.lsp.enable("verse", true)
      end)
    end)
  else
    vim.notify("Couldn't write fix to " .. vproject_file,
      vim.log.levels.WARN, { title = "verse.nvim" })
  end
end

return M
