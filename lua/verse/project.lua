local M = {}

local function file_match(pat)
  return function(name, _)
    return name:match(pat) ~= nil
  end
end

--- Finds the root directory for a Verse project.
--- @return string?
function M.find_root_dir(fname)
  return vim.fs.root(fname, file_match(".vproject$")) or
    vim.fs.root(fname, file_match(".uefnproject$")) or
    vim.fs.root(fname, file_match(".uplugin$"))
end

--- Guesses the AppData/Local directory when $LocalAppData is not present.
--- @param root_dir string Root directory
--- @return string?
local function guess_local_appdata(root_dir)
  local user_prefix = root_dir:match("^(.-/Users/.-/)")
  if user_prefix == nil then
    return nil
  end
  return vim.fs.joinpath(user_prefix, "AppData", "Local")
end

--- Non-recursively finds files matching a pattern in a directory.
--- @param dir string Directory path
--- @param pat string Pattern to match
--- @return string[]
local function find_in_dir(dir, pat)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return {}
  end

  local result = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "file" and name:match(pat) then
      table.insert(result, vim.fs.joinpath(dir, name))
    end
  end
  return result
end

--- Finds the .vproject file relevant to the given file.
--- @param root_dir string Root direcotry path
--- @return string? vproject_file, string? project_name
function M.find_vproject_file(root_dir)
  root_dir = vim.fs.normalize(root_dir)

  -- look for .vproject file directly
  local vproject_search_result = find_in_dir(root_dir, ".vproject$")
  if #vproject_search_result > 1 then
    vim.notify("Found several .vproject files in root directory.",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return nil, nil
  elseif #vproject_search_result == 1 then
    return vproject_search_result[1]
  end

  -- if we are in a UEFN project, find .vproject from AppData
  local project_name = vim.fs.basename(root_dir)
  local uefnproject_search_result = find_in_dir(root_dir, ".uefnproject$")
  if #uefnproject_search_result > 1 then
    vim.notify("Found several .uefnproject files in root directory.",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return nil, project_name
  elseif #uefnproject_search_result == 1 then
    project_name = vim.fn.fnamemodify(uefnproject_search_result[1], ":t:r")
  end

  local appdata_dir = os.getenv("LocalAppData") or guess_local_appdata(root_dir)
  if appdata_dir ~= nil then
    local vproject_file = vim.fs.joinpath(appdata_dir,
      "UnrealEditorFortnite", "Saved", "VerseProject", project_name, "vproject", project_name .. ".vproject")
    if vim.uv.fs_stat(vproject_file) then
      return vproject_file, project_name
    end
  end

  -- maybe we're in a VerseProject directory and need to ping pong
  local verseprojects_dir_search_result = vim.fs.find(
    "VerseProject",
    { path = root_dir, type = "directory", limit = 1, upward = true }
  )
  if #verseprojects_dir_search_result > 0 then
    local verseprojects_dir = verseprojects_dir_search_result[1]
    project_name = root_dir:sub(#verseprojects_dir + 2):match("([^/]+)")
    local verseproject_dir = vim.fs.joinpath(verseprojects_dir, project_name)
    if verseproject_dir ~= nil then
      vproject_search_result = vim.fs.find(
        file_match(".vproject$"),
        { path = verseproject_dir, type = "file", limit = 1, upward = false }
      )
      if #vproject_search_result > 0 then
        return vproject_search_result[1], project_name
      end
    end
  end

  return nil, project_name
end

--- @class verse.project.GetWorkspaceFoldersOpts
---
--- Whether to allow the use of a virtual .vproject when the paths
--- linked in the original .vproject are known to be incorrect and can be corrected.
--- @field allow_virtual_vproject? boolean
---
--- Whether to prevent creating a temporary file for the virtual .vproject file.
--- This should remain `false` when the resulting workspace folders will be fed to the LSP server.
--- @field read_only? boolean

--- Gets required LSP workspace folders to register for a Verse project to load properly.
--- @param root_dir string Root directory path
--- @param opts? verse.project.GetWorkspaceFoldersOpts
--- @return lsp.WorkspaceFolder[] workspace_folders, string? vproject_file
function M.get_workspace_folders_from_root_dir(root_dir, opts)
  local vproject_file, project_name = M.find_vproject_file(root_dir)
  if vproject_file ~= nil then
    return M.get_workspace_folders_from_vproject_file(vproject_file, opts), vproject_file
  end

  -- attempt to fall back on the folders from the generated .code-workspace file
  local codews_search_result = vim.fs.find(
    project_name .. ".code-workspace",
    { path = root_dir, type = "file", limit = 1, upward = false }
  )
  if #codews_search_result > 0 then
    local file_contents = table.concat(vim.fn.readfile(codews_search_result[1]), "\n")
    local ok, json = pcall(vim.json.decode, file_contents)
    if not ok then
      vim.notify(".vproject not found, found a .code-workspace file instead but it isn't valid JSON (trailing comma?)",
        vim.log.levels.WARN, { title = "verse.nvim" })
      return {}
    end
    local folders = json["folders"]
    if folders ~= nil then
      local result = {}
      for _, folder in ipairs(folders) do
        local normalized_dir_path = vim.fs.normalize(folder["path"])
        table.insert(result, {
          name = normalized_dir_path,
          uri = vim.uri_from_fname(normalized_dir_path),
        })
      end
      if #result > 0 then
        return result, nil
      end
    end
  end

  vim.notify("Couldn't find Verse project, open a file from a UEFN project or create a .vproject file.",
    vim.log.levels.WARN, { title = "verse.nvim" })
  return {}, nil
end

--- Returns the "volume prefix" part of a path.
--- @return string
local function get_volume_prefix(path)
  return path:match("^(.-)/Users/")
end

--- Remaps vproject JSON with file paths adapted to the desired volume prefix.
--- @param json table Decoded JSON of the original .vproject
--- @param desired_volume_prefix string Desired volume prefix to conform the packages to
local function remap_json_to_virtual_vproject(json, desired_volume_prefix)
  for _, package in ipairs(json["packages"]) do
    local desc = package["desc"]
    if desc ~= nil then
      local dir_path = desc["dirPath"]
      if dir_path ~= nil then
        local path_post_volume = dir_path:match("^.-(/Users/.+)$")
        desc["dirPath"] = vim.fs.joinpath(desired_volume_prefix, path_post_volume)
      end
    end
  end
end

--- Gets required LSP workspace folders to register for a .vproject to work as intended.
--- @param vproject_file string .vproject file path
--- @param opts? verse.project.GetWorkspaceFoldersOpts
--- @return lsp.WorkspaceFolder[]
function M.get_workspace_folders_from_vproject_file(vproject_file, opts)
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, {
    allow_virtual_vproject = true,
    read_only = false,
  })

  vproject_file = vim.fs.normalize(vproject_file)
  local file_contents = table.concat(vim.fn.readfile(vproject_file), "\n")
  local json = vim.json.decode(file_contents)
  if json == nil then
    vim.notify("Invalid JSON in .vproject file: " .. vproject_file,
      vim.log.levels.WARN, { title = "verse.nvim" })
    return {}
  end
  local packages = json["packages"]
  if packages == nil then
    vim.notify("Unexpected .vproject format for " .. vproject_file,
      vim.log.levels.WARN, { title = "verse.nvim" })
    return {}
  end

  --- @type string?
  local vproject_root_dir = vim.fs.dirname(vproject_file)

  -- since UEFN is currently Windows only, this is a hack to allow
  -- opening files under a virtual machine from the host system
  if opts.allow_virtual_vproject and vim.uv.os_uname().sysname ~= "Windows_NT" then
    local expected_volume_prefix = get_volume_prefix(vproject_file)
    local use_virtual_vproject = false
    for _, package in ipairs(packages) do
      local desc = package["desc"]
      if desc ~= nil then
        local dir_path = desc["dirPath"]
        if dir_path ~= nil and get_volume_prefix(dir_path) ~= expected_volume_prefix then
          use_virtual_vproject = true
          break
        end
      end
    end

    if use_virtual_vproject then
      remap_json_to_virtual_vproject(json, expected_volume_prefix)
      if opts.read_only then
        vproject_root_dir = nil
      else
        local tmp_dir = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/vvproj.XXXXXXXX")
        local new_file_contents = vim.json.encode(json)
        local tmp_vproject_file = vim.fs.joinpath(tmp_dir, "virtual.vproject")
        local fd = vim.uv.fs_open(tmp_vproject_file, "w", tonumber("644", 8))
        if fd ~= nil then
          vim.uv.fs_write(fd, new_file_contents, -1)
          vim.uv.fs_close(fd)
          vproject_root_dir = tmp_vproject_file
        else
          vim.notify("Failed to create virtual .vproject to circumvent external files of " .. vproject_file,
            vim.log.levels.WARN, { title = "verse.nvim" })
          return {}
        end
      end
    end
  end

  local result = {}
  if vproject_root_dir ~= nil then
    local vproject_result_entry ={
      name = vproject_root_dir,
      uri = vim.uri_from_fname(vproject_root_dir),
    }
    table.insert(result, vproject_result_entry)
  end
  for _, package in ipairs(packages) do
    local desc = package["desc"]
    if desc ~= nil then
      local role
      local settings = desc["settings"]
      if settings ~= nil then
        role = settings["role"]
      end
      role = role or ""

      local dir_path = desc["dirPath"]
      if dir_path ~= nil and role ~= "PersistenceCompatConstraint" then
        local normalized_dir_path = vim.fs.normalize(dir_path)
        table.insert(result, {
          name = normalized_dir_path,
          uri = vim.uri_from_fname(normalized_dir_path),
        })
      end
    end
  end
  return result
end

--- @class verse.project.GetActiveWorkspaceFoldersOpts
--- @field bufnr? integer Target buffer number

--- Gets the workspace folders of the currently active project.
--- If the LSP server is not running, defaults back to finding required workspace folders.
--- @param opts? verse.project.GetActiveWorkspaceFoldersOpts
--- @return lsp.WorkspaceFolder[]
function M.get_active_workspace_folders(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local verse_lsp_clients = vim.lsp.get_clients({
    bufnr = bufnr,
    name = "verse",
  })
  local workspace_folders = {}
  for _, client in ipairs(verse_lsp_clients) do
    if client.workspace_folders ~= nil then
      vim.list_extend(workspace_folders, client.workspace_folders)
    end
  end

  if #workspace_folders < 1 then
    local root_dir = M.find_root_dir(vim.fn.expand("%:p"))
    if root_dir == nil then
      vim.notify("Couldn't find a running LSP server or a project root to list digest files",
        vim.log.levels.WARN, { title = "verse.nvim" })
      return {}
    end

    local project_folders, _ = M.get_workspace_folders_from_root_dir(root_dir, {
      read_only = true,
    })
    workspace_folders = project_folders
  end

  return workspace_folders
end

--- Lists the relevant .digest.verse files of the current project.
--- @param opts? verse.project.GetActiveWorkspaceFoldersOpts
--- @return string[] # Digest file names
function M.list_digest_files(opts)
  local workspace_folders = M.get_active_workspace_folders(opts)
  local digest_files = {}
  for _, workspace_folder in ipairs(workspace_folders) do
    local search_result = vim.fs.find(
      file_match(".digest.verse$"),
      { path = workspace_folder.name, type = "file", limit = math.huge, upward = false }
    )
    vim.list_extend(digest_files, search_result)
  end
  return digest_files
end

--- `list_digest_files` is blocking and can be noticeably slow on large projects.
--- This provides a file finder shell command to feed fzf or whatever picker.
--- Uses the `fd` command.
--- @param opts? verse.project.GetActiveWorkspaceFoldersOpts
--- @return string # Command line
function M.list_digest_files_cmd(opts)
  local workspace_folders = M.get_active_workspace_folders(opts)

  local fd_bin = "fd"
  if vim.fn.executable("fdfind") == 1 then
    fd_bin = "fdfind"
  end
  local cmd = fd_bin .. " --color=never --type f --type l \\.digest.verse$"
  for _, workspace_folder in ipairs(workspace_folders) do
    cmd = cmd .. " " .. vim.fn.shellescape(workspace_folder.name)
  end
  return cmd
end

return M
