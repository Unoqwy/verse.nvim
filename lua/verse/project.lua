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

--- Gets required LSP workspace folders to register for a Verse project to load properly.
--- @param root_dir string Root directory path
--- @return lsp.WorkspaceFolder[]
function M.get_workspace_folders_from_root_dir(root_dir)
  -- look for .vproject file directly
  local vproject_search_result = find_in_dir(root_dir, ".vproject$")
  if #vproject_search_result > 1 then
    vim.notify("Found several .vproject files in root directory.",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return {}
  elseif #vproject_search_result == 1 then
    return M.get_workspace_folders_from_vproject(vproject_search_result[1])
  end

  -- if we are in a UEFN project, find .vproject from AppData
  local project_name = vim.fs.basename(root_dir)
  local uefnproject_search_result = find_in_dir(root_dir, ".uefnproject$")
  if #uefnproject_search_result > 1 then
    vim.notify("Found several .uefnproject files in root directory.",
      vim.log.levels.WARN, { title = "verse.nvim" })
    return {}
  elseif #uefnproject_search_result == 1 then
    project_name = vim.fn.fnamemodify(uefnproject_search_result[1], ":t:r")
  end

  local appdata_dir = os.getenv("LocalAppData") or guess_local_appdata(root_dir)
  if appdata_dir ~= nil then
    local vproject_file = vim.fs.joinpath(appdata_dir,
      "UnrealEditorFortnite", "Saved", "VerseProject", project_name, "vproject", project_name .. ".vproject")
    if vim.uv.fs_stat(vproject_file) then
      return M.get_workspace_folders_from_vproject(vproject_file)
    end
  end

  -- attempt to fall back on the generated .code-workspace file
  local codews_search_result = vim.fs.find(
    project_name .. ".code-workspace",
    { path = root_dir, type = "file", limit = 1 }
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
        return result
      end
    end
  end

  vim.notify("Couldn't find Verse project, open a file from a UEFN project or create a .vproject file.",
    vim.log.levels.WARN, { title = "verse.nvim" })
  return {}
end

--- Returns the "volume prefix" part of a path.
--- @return string
local function get_volume_prefix(path)
  return path:match("^(.-)/Users/")
end

--- Creates a virtual .vproject file with file paths adapted to the desired volume prefix.
--- This is only used when the host system is not Windows.
--- @param json table Decoded JSON of the original .vproject
--- @param desired_volume_prefix string Desired volume prefix to conform the packages to
local function create_virtual_vproject(json, desired_volume_prefix)
  local tmp_dir = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/vvproj.XXXXXXXX")

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

  local file_contents = vim.json.encode(json)
  local tmp_vproject_file = vim.fs.joinpath(tmp_dir, "virtual.vproject")
  local fd = vim.uv.fs_open(tmp_vproject_file, "w", tonumber("644", 8))
  if fd ~= nil then
    vim.uv.fs_write(fd, file_contents, -1)
    vim.uv.fs_close(fd)
    return tmp_vproject_file
  end
end

--- Gets required LSP workspace folders to register for a .vproject to work as intended.
--- @param vproject_file string .vproject file path
--- @return lsp.WorkspaceFolder[]
function M.get_workspace_folders_from_vproject(vproject_file)
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

  local vproject_root_dir = vim.fs.dirname(vproject_file)

  -- since UEFN is currently Windows only, this is a hack to allow
  -- opening files under a virtual machine from the host system
  if vim.uv.os_uname().sysname ~= "Windows_NT" then
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
      vproject_root_dir = create_virtual_vproject(json, expected_volume_prefix)
      if vproject_root_dir == nil then
        vim.notify("Failed to create virtual .vproject to circumvent external files of " .. vproject_file,
          vim.log.levels.WARN, { title = "verse.nvim" })
        return {}
      end
    end
  end

  local vproject_result_entry = {
    name = vproject_root_dir,
    uri = vim.uri_from_fname(vproject_root_dir),
  }
  local result = { vproject_result_entry }
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

return M

