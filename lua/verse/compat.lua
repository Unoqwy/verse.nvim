local wsl_exe_compat_injected = false

local M = {}

--- Returns whether we are under WSL.
--- @return boolean
function M.using_wsl()
  return os.getenv("WSL_DISTRO_NAME") ~= nil
end

--- Gets the Windows User Directory from within WSL.
--- @return string? Directory path
function M.get_wsl_windows_user_directory()
  local cmd_result = vim.system({"cmd.exe", "/c", "echo", "%USERNAME%"}):wait()
  if cmd_result.code ~= 0 then
    return nil
  end
  local win_username = vim.fn.trim(cmd_result.stdout)
  return vim.fs.joinpath("/mnt", "c", "Users", win_username)
end

--- Injects a path transformer into vim.uri_to_fname to remap X:\ paths to /mnt/x.
--- This is used when using verse-lsp.exe on WSL instead of Linux/verse-lsp,
--- notably required when running on arm64.
function M.inject_incoming_wsl_path_transformer()
  if wsl_exe_compat_injected then
    return
  end
  wsl_exe_compat_injected = true

  local orig_fn_utf = vim.uri_to_fname
  vim.uri_to_fname = function(uri)
    uri = M._win_to_wsl_uri(uri)
    return orig_fn_utf(uri)
  end
end

--- Injects a path transformer into outgoing LSP requests.
--- @param client vim.lsp.Client
function M.inject_outgoing_wsl_path_transformer(client)
  if client["verse_wsl_exe_compat_injected"] then
    return
  end
  client["verse_wsl_exe_compat_injected"] = true
  local orig_fn_notify = client.notify
  client.notify = function(self, method, params)
    M._uri_transform_lsp_params(params)
    return orig_fn_notify(self, method, params)
  end
end

--- @param params table
--- @return nil # Transformed in place
function M._uri_transform_lsp_params(params)
  if type(params) ~= "table" then
    return
  end

  local stack = { params }
  while #stack > 0 do
    local current = table.remove(stack)
    for key, value in pairs(current) do
      if key == "uri" and type(value) == "string" then
        current[key] = M._to_win_uri(value)
      elseif type(value) == "table" then
        table.insert(stack, value)
      end
    end
  end
end

--- Converts workspace folders given the LSP server to workspace folders
--- with paths understable by neovim.
--- @param lsp_workspace_folders lsp.WorkspaceFolder[]
--- @return lsp.WorkspaceFolder[] nvim_workspace_folders
function M.lsp_to_nvim_workspace_folders(lsp_workspace_folders)
  local result = {}
  for _, lsp_workspace_folder in ipairs(lsp_workspace_folders) do
    local new_fname = M._win_to_wsl_fname(lsp_workspace_folder.name)
    table.insert(result, {
      name = new_fname,
      uri = vim.uri_from_fname(new_fname),
    })
  end
  return result
end

--- @param uri string
--- @return string
function M._to_win_uri(uri)
  local drive, path = uri:match("^file:///mnt/([a-z])/(.+)$")
  if drive ~= nil and path ~= nil then
    return "file://" .. vim.fs.joinpath(drive:upper() .. ":", vim.fs.normalize(path))
  end
  return uri
end

--- @param uri string
--- @return string
function M._win_to_wsl_uri(uri)
  local drive, path = uri:match("^file:///([A-Z])%%3A(.+)$")
  if drive ~= nil and path ~= nil then
    return "file://" .. vim.fs.joinpath("/mnt", drive:lower(), vim.fs.normalize(path))
  end
  return uri
end

--- @param fname string
--- @return string
function M._win_to_wsl_fname(fname)
  local drive, path = fname:match("^([A-Z]):(.+)$")
  if drive ~= nil and path ~= nil then
    return vim.fs.joinpath("/mnt", drive:lower(), vim.fs.normalize(path))
  end
  return fname
end

return M
