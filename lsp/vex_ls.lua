-- A complementary open-source LSP server focused on speed and features support rather than error checking.

local vproject = require("verse.project")

---@type vim.lsp.Config
return {
  name = "vex_ls",
  filetypes = { "verse" },
  cmd = { "vex_ls" },
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    on_dir(vproject.find_root_dir(fname))
  end,
  reuse_client = function(client, config)
    local root_dir = config.root_dir or vim.fn.expand("%:p:h")
    local vproject_file = vproject.find_vproject_file_from_root_dir(root_dir)
    return client.name == "vex_ls"
      and vproject_file ~= nil and client.config["vproject_file"] == vproject_file
  end,
  before_init = function(params, config)
    local lsp_bin = type(config.cmd) == "table" and config.cmd[1] or nil

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
    config.workspace_folders = lsp_workspace_folders
  end,
  on_init = function(client, _)
    -- sync client state for list_workspace_folders() to work properly
    client.workspace_folders = client.config.workspace_folders
  end,
}
