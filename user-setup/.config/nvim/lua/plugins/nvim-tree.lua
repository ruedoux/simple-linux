local M = {}

function M.setup(config)
  local hidden_vimregexes = vim.tbl_map(config._to_vimregex, config.hiddenPatterns)

  require("nvim-tree").setup({
    view = {
      width = 35,
    },
    filters = {
      dotfiles = false,
      git_ignored = false,
      custom = hidden_vimregexes,
    },
    renderer = {
      group_empty = true,
    },
  })

  vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = "none" })
  vim.api.nvim_set_hl(0, "SignColumn", { bg = "none" })
  vim.api.nvim_set_hl(0, "NvimTreeSignColumn", { bg = "none" })
  vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = "none" })
  vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = "#2a2a2a", bg = "none" })
  vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { bg = "none" })
end

return M
