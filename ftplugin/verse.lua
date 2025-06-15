if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = true

vim.opt_local.commentstring = "# %s"

