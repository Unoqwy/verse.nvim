local verse = require("verse")
local notify = verse.create_notifier("Verse LSP Finder")
local log_level = vim.log.levels

local M = {}

local function get_matching_dirs(base, match)
  local dirs = {}
  local handle = vim.uv.fs_scandir(base)
  if not handle then
    return dirs
  end

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "directory" and name:match(match) then
      table.insert(dirs, vim.fs.joinpath(base, name))
    end
  end

  return dirs
end

--- Returns the directory path where the VSCode extensions should be extracted by the plugin.
--- @return string
local function get_extracted_extensions_dir()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "verse", "extensions")
end

--- Finds the most recent installed version of epicgames.verse VSCode extension.
--- @param home_dirs string[] Home directories to look from
--- @return string? ext_dir, string? ext_version
function M._find_installed_extension(home_dirs)
  local ext_parent_dirs = {}

  table.insert(ext_parent_dirs, get_extracted_extensions_dir())
  for _, home in ipairs(home_dirs) do
    table.insert(ext_parent_dirs, vim.fs.joinpath(home, ".vscode", "extensions"))
    table.insert(ext_parent_dirs, vim.fs.joinpath(home, ".cursor", "extensions"))
    table.insert(ext_parent_dirs, vim.fs.joinpath(home, ".antigravity", "extensions"))
  end

  local all_matching_dirs = {}
  for _, path in ipairs(ext_parent_dirs) do
    for _, matching_dir in ipairs(get_matching_dirs(path, "^epicgames.verse")) do
      table.insert(all_matching_dirs, {
        dir = matching_dir,
        ext_version = vim.fs.basename(matching_dir):gsub("^epicgames.verse%-", ""),
      })
    end
  end
  if #all_matching_dirs < 1 then
    return nil, nil
  end

  table.sort(all_matching_dirs, function(a, b)
    return a.ext_version > b.ext_version
  end)
  return all_matching_dirs[1].dir, all_matching_dirs[1].ext_version
end

--- Attempts to extract the Verse extension shipped with the UEFN installation.
--- @param found_version string? Found Verse extension version. Will only extract if greater than this
--- @return string? # Newly extracted extension directory
function M._extract_uefn_extension(found_version)
  local vsix_path = verse.get_config().uefn_extract.vsix_path
  if vsix_path == nil then
    local uname = vim.uv.os_uname()
    local os = uname.sysname
    local using_wsl = require("verse.compat.wsl").using_wsl()

    if os == "Windows_NT" or using_wsl then
      local program_files_dir = require("verse.compat.wsl").get_windows_env("ProgramW6432")
      if program_files_dir == nil then
        return nil
      end
      if using_wsl then
        program_files_dir = require("verse.compat.wsl").win_to_wsl_fname(program_files_dir)
      end
      vsix_path = vim.fs.joinpath(program_files_dir, "Epic Games", "Fortnite", "VSCode", "Verse.vsix")
    else
      -- UEFN is only compatible with Windows at the moment, so there can't be native installations here
      -- TODO: for macOS maybe try the CrossOver bottles scanning
      notify("Unsupported system to find Verse.vsix", log_level.DEBUG)
      return nil
    end
  end

  if not vim.uv.fs_stat(vsix_path) then
    notify("Verse.vsix not found at path: " .. vsix_path, log_level.DEBUG)
    return nil
  end

  -- FIXME: on Windows (no WSL), use an alternative to `unzip`
  if os == "Windows_NT" then
    return nil
  end

  local manifest_result = vim.system(
    {"unzip", "-p", vsix_path, "extension.vsixmanifest"},
    { text = true }
  ):wait(1500)
  if manifest_result.code ~= 0 then
    notify(string.format("VSIX Manifest `unzip -p` failed. Code: %d", manifest_result.code), log_level.DEBUG)
    return nil
  end

  local content = vim.fn.trim(manifest_result.stdout or "")
  local vsix_version = content:match("<Identity[^>]-Version=\"([^\"]+)\"")

  notify(string.format("Verse.vsix version: %s, found installed version: %s", vsix_version, found_version), log_level.DEBUG)
  if found_version >= vsix_version then
    return nil
  end

  local vsix_id = content:match("<Identity[^>]-Id=\"([^\"]+)\"")
  local vsix_publisher = content:match("<Identity[^>]-Publisher=\"([^\"]+)\"")

  local ext_dir_name = string.format("%s.%s-%s", vsix_publisher, vsix_id, vsix_version)
  if not ext_dir_name:match("^epicgames.verse") then
    return nil
  end

  notify(string.format("Verse.vsix is newer than currently installed, extracting %s...", ext_dir_name), log_level.INFO)

  local extensions_dir = get_extracted_extensions_dir()
  vim.fn.mkdir(extensions_dir, "p")

  local extracted_ext_dir = vim.fs.joinpath(extensions_dir, ext_dir_name)

  local tmp_extract_dir = vim.fs.joinpath(extensions_dir, "tmp")
  local extract_result = vim.system(
    {"unzip", "-d", tmp_extract_dir, vsix_path, "extension/bin/*"},
    { text = true }
  ):wait(3000)
  if extract_result.code == 0 then
    vim.uv.fs_rename(vim.fs.joinpath(tmp_extract_dir, "extension"), extracted_ext_dir)
  else
    notify("Verse.vsix failed to extract: " .. extract_result.stderr, log_level.WARN)
  end
  vim.uv.fs_rmdir(tmp_extract_dir)

  if vim.uv.fs_stat(extracted_ext_dir) then
    vim.schedule(function()
      notify("Verse.vsix extracted successfully", log_level.INFO)
    end)
    return extracted_ext_dir
  else
    return nil
  end
end

--- Finds the Verse LSP server binary path, possibly not an existing file.
--- @return string?
function M._find_lsp_binary_path()
  local using_wsl = require("verse.compat.wsl").using_wsl()

  local home_dirs = {
    vim.fn.expand("$HOME"),
  }
  if using_wsl then
    local win_user_dir = require("verse.compat.wsl").get_wsl_windows_user_directory()
    if win_user_dir ~= nil then
      table.insert(home_dirs, win_user_dir)
    end
  end

  local latest_ext_dir, latest_ext_version = M._find_installed_extension(home_dirs)

  if verse.get_config().uefn_extract.enabled == true then
    local extracted_ext_dir = M._extract_uefn_extension(latest_ext_version)
    if extracted_ext_dir ~= nil then
      latest_ext_dir = extracted_ext_dir
    end
  end

  if latest_ext_dir == nil then
    return nil
  end

  local bin_dir = vim.fs.joinpath(latest_ext_dir, "bin")
  local uname = vim.uv.os_uname()

  if using_wsl then
    if uname.machine == "aarch64" then
      -- at the moment there is no provided arm64 linux LSP server binary
      -- so let's use the .exe to run on Windows layer that has arm64->x86_64 translation
      -- this effectively limits the LSP to opening vprojects only from the Windows filesystem
      -- and also requires the file path transformer from verse.compat
      return vim.fs.joinpath(latest_ext_dir, "bin", "Win64", "verse-lsp.exe")
    end
    return vim.fs.joinpath(latest_ext_dir, "bin", "Linux", "verse-lsp")
  else
    local os = uname.sysname
    if os == "Windows_NT" then
      return vim.fs.joinpath(bin_dir, "Win64", "verse-lsp.exe")
    elseif os == "Darwin" then
      return vim.fs.joinpath(bin_dir, "Mac", "verse-lsp")
    elseif os == "Linux" then
      return vim.fs.joinpath(bin_dir, "Linux", "verse-lsp")
    end
  end
end

--- Finds the Verse LSP server binary.
--- @return string? # Server binary path confirmed to exist, or nil
function M.find_lsp_binary()
  local path = require("verse.lsp_finder")._find_lsp_binary_path()

  if not path or not vim.uv.fs_stat(path) then
    notify("Epic's LSP server couldn't be found. Try installing the VSCode extension or set path overrides in verse.nvim config", log_level.WARN)
    return nil
  end

  return path
end

return M
