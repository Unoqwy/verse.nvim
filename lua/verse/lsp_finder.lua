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
--- @return string? # Extension directory path
local function find_installed_extension()
  local home = vim.fn.expand("$HOME")
  local ext_parent_dirs = {
    vim.fs.joinpath(home, ".vscode", "extensions"),
    vim.fs.joinpath(home, ".cursor", "extensions"),
    vim.fs.joinpath(home, ".windsurf", "extensions"),
  }

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
  local latest_ext_dir = find_installed_extension()
  if not latest_ext_dir then
    return nil
  end

  local bin_dir = vim.fs.joinpath(latest_ext_dir, "bin")
  local os = vim.uv.os_uname().sysname
  if os == "Windows_NT" then
    return vim.fs.joinpath(bin_dir, "Win64", "verse-lsp.exe")
  elseif os == "Darwin" then
    return vim.fs.joinpath(bin_dir, "Mac", "verse-lsp")
  elseif os == "Linux" then
    return vim.fs.joinpath(bin_dir, "Linux", "verse-lsp")
  end
end

return M
