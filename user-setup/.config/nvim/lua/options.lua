local M = {}

function M.setup(config)
  for k, v in pairs(config.options) do
    vim.opt[k] = v
  end
  for k, vals in pairs(config.option_appends) do
    for _, v in ipairs(vals) do
      vim.opt[k]:append(v)
    end
  end
  for k, v in pairs(config.globals) do
    vim.g[k] = v
  end

  vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/site")

  local undodir = vim.fn.expand("~/.vim/undodir")
  if vim.fn.isdirectory(undodir) == 0 then
    vim.fn.mkdir(undodir, "p")
  end
  vim.opt.undodir = undodir
end

return M
