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

--- Finds the most recent installed version of epicgames.verse VSCode extension.
--- @param home_dirs string[] Home directories to look from
--- @return string? # Extension directory path
function M._find_installed_extension(home_dirs)
  local ext_parent_dirs = {}
  for _, home in ipairs(home_dirs) do
    table.insert(ext_parent_dirs, vim.fs.joinpath(home, ".vscode", "extensions"))
    table.insert(ext_parent_dirs, vim.fs.joinpath(home, ".cursor", "extensions"))
    table.insert(ext_parent_dirs, vim.fs.joinpath(home, ".windsurf", "extensions"))
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
    return nil
  end

  table.sort(all_matching_dirs, function(a, b)
    return a.ext_version > b.ext_version
  end)
  return all_matching_dirs[1].dir
end

--- Finds the Verse LSP server binary.
--- @return string?
function M.find_lsp_binary()
  local using_wsl = require("verse.compat").using_wsl()

  local home_dirs = {
    vim.fn.expand("$HOME"),
  }
  if using_wsl then
    local win_user_dir = require("verse.compat").get_wsl_windows_user_directory()
    if win_user_dir ~= nil then
      table.insert(home_dirs, win_user_dir)
    end
  end

  local latest_ext_dir = M._find_installed_extension(home_dirs)
  if latest_ext_dir == nil then
    return nil
  end

  local bin_dir = vim.fs.joinpath(latest_ext_dir, "bin")
  local uname = vim.uv.os_uname()

  if using_wsl then
    if vim.uv.os_uname().machine == "aarch64" then
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

return M
