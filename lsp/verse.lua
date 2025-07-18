local vproject = require("verse.project")

local function default_cmd()
  local lsp_bin = require("verse.lsp_finder").find_lsp_binary()
  if not lsp_bin or not vim.uv.fs_stat(lsp_bin) then
    return vim.notify("Verse LSP server could not be found. Is the official VSCode extension installed?",
      vim.log.levels.WARN, { title = "verse.nvim" })
  end

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

  return { lsp_bin }
end

---@type vim.lsp.Config
return {
  name = "verse",
  filetypes = { "verse" },
  cmd = default_cmd(),
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
    local lsp_bin = type(config.cmd) == "table" and config.cmd[1] or nil

    local compat = require("verse.compat")
    if lsp_bin ~= nil and compat.using_wsl() and lsp_bin:match(".exe$") then
      config["verse_wsl_exe_compat"] = true
      compat.inject_incoming_wsl_path_transformer()
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
      config.workspace_folders = compat.lsp_to_nvim_workspace_folders(lsp_workspace_folders)
    else
      config.workspace_folders = lsp_workspace_folders
    end
  end,
  on_init = function(client, _)
    -- sync client state for list_workspace_folders() to work properly
    client.workspace_folders = client.config.workspace_folders

    if client.config["verse_wsl_exe_compat"] then
      require("verse.compat").inject_outgoing_wsl_path_transformer(client)
    end
  end,
  on_attach = function(client, bufnr)
    vim.b[bufnr].vproject_file = client.config["vproject_file"]
  end,
}

