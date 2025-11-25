local vproject = require("verse.project")

--- @param lsp_bin string LSP binary path
local function ensure_binary_executable(lsp_bin)
  if vim.fn.executable(lsp_bin) == 0 then
    local os = vim.uv.os_uname().sysname
    local made_exec = false
    if os == "Darwin" or os == "Linux" then
      vim.fn.system({ "chmod", "+x", lsp_bin })
      if vim.v.shell_error == 0 then
        made_exec = true
      end
    end
    if not made_exec then
      return vim.notify("Verse LSP server is not executable and could not be made executable.",
        vim.log.levels.WARN, { title = "verse.nvim" })
    end
  end
end

--- Resolves the default LSP cmd by finding the binary.
--- @return string[]
local function resolve_default_cmd()
  local lsp_bin = require("verse.lsp_finder").find_lsp_binary()
  if lsp_bin == nil then
    return {}
  end
  return { lsp_bin }
end

--- @type vim.lsp.Config
return {
  name = "verse",
  filetypes = { "verse", "vproject" },
  cmd = function(dispatchers, config)
    local verse_config = require("verse").get_config()

    local tcp_mode = verse_config.lsp_tcp_mode or {}
    if tcp_mode.enabled == true then
      return vim.lsp.rpc.connect(tcp_mode.address or "127.0.0.1", tcp_mode.port)(dispatchers)
    end

    --- @type any
    local cmd = {}
    if verse_config.lsp_binary ~= nil then
      if type(verse_config.lsp_binary) == "string" then
        cmd = { verse_config.lsp_binary }
      else
        cmd = verse_config.lsp_binary
      end
    else
      cmd = resolve_default_cmd()
    end
    config["last_resolved_cmd"] = cmd

    local lsp_bin = cmd[1]
    if lsp_bin ~= nil then
      ensure_binary_executable(lsp_bin)
    end

    return vim.lsp.rpc.start(cmd, dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
      detached = config.detached,
    })
  end,
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    on_dir(vproject.find_root_dir(fname))
  end,
  reuse_client = function(client, config)
    local root_dir = config.root_dir or vim.fn.expand("%:p:h")
    local vproject_file = vproject.find_vproject_file_from_root_dir(root_dir)
    return vproject_file ~= nil and client.config["vproject_file"] == vproject_file
  end,
  before_init = function(params, config)
    local lsp_bin
    if config["last_resolved_cmd"] ~= nil then
      local true_cmd = config["last_resolved_cmd"]
      lsp_bin = true_cmd[1]

      -- set to resolved cmd to view it from `:checkhealth vim.lsp`
      config.cmd = true_cmd
    else
      lsp_bin = type(config.cmd) == "table" and config.cmd[1] or nil
    end

    if lsp_bin ~= nil and lsp_bin:match(".exe$") and require("verse.compat.wsl").using_wsl() then
      config["verse_wsl_exe_compat"] = true
      require("verse.compat.wsl").inject_incoming_wsl_path_transformer()
    end

    local root_dir = config.root_dir or vim.fn.expand("%:p:h")
    local project_folders, vproject_file = vproject
      .get_workspace_folders_from_root_dir(root_dir, { lsp_bin = lsp_bin })
    config["vproject_file"] = vproject_file

    local lsp_workspace_folders = params["workspaceFolders"] or {}
    if require("verse").get_config().vproject_workspace_folders_only then
      lsp_workspace_folders = project_folders
    else
      vim.list_extend(lsp_workspace_folders, project_folders)
    end
    params["workspaceFolders"] = lsp_workspace_folders
    if config["verse_wsl_exe_compat"] then
      config.workspace_folders = require("verse.compat.wsl").lsp_to_nvim_workspace_folders(lsp_workspace_folders)
    else
      config.workspace_folders = lsp_workspace_folders
    end
  end,
  on_init = function(client, _)
    -- sync client state for list_workspace_folders() to work properly
    client.workspace_folders = client.config.workspace_folders

    if client.config["verse_wsl_exe_compat"] then
      require("verse.compat.wsl").inject_outgoing_wsl_path_transformer(client)
    end

    require("verse.compat.nil_suppression").inject_nil_suppression(client)
  end,
  on_attach = function(client, bufnr)
    vim.b[bufnr].vproject_file = client.config["vproject_file"]
  end,
}

