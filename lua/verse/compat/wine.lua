local M = {}

--- Attempts to resolve a Windows path into a Wine prefixed path.
--- This will look through all recognized Wine filesystems and could theoretically
--- be mapped to the wrong Wine prefix. That is to keep full automated inference
--- by not requiring the prefix to be specified by the user.
--- It's unlikely to be a problem for the actual use case, but TODO : More magic?
--- @param win_path string Windows format path
--- @return string? Wine prefixed path in the local filesystem
function M.resolve_wine_path(win_path)
  local drive, path = win_path:match("^([A-Z]):(.+)$")
  if drive == nil or path == nil then
    return nil
  end

  local home_dir = vim.fn.expand("$HOME")
  local crossover_bottles_dir = vim.fs.joinpath(home_dir, "/Library/Application Support/CrossOver/Bottles")
  local handle = vim.uv.fs_scandir(crossover_bottles_dir)
  if not handle then
    return nil
  end
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if name == nil then
      break
    end
    if type == "directory" then
      local bottle_dir = vim.fs.joinpath(crossover_bottles_dir, name)
      local drive_dir = vim.fs.joinpath(bottle_dir, "drive_" .. drive:lower())
      local full_mapped_path = vim.fs.joinpath(drive_dir, vim.fs.normalize(path))
      if vim.uv.fs_stat(full_mapped_path) then
        return full_mapped_path
      end
    end
  end
  return nil
end

return M
