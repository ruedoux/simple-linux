local M = {}

function M.setup(cfg)
  vim.opt.termguicolors = true
  vim.cmd.colorscheme(cfg.colorscheme)

  if cfg.transparent then
    local groups = {
      "Normal",
      "NormalNC",
      "EndOfBuffer",
      "NormalFloat",
      "FloatBorder",
      "SignColumn",
      "StatusLine",
      "StatusLineNC",
      "TabLine",
      "TabLineFill",
      "TabLineSel",
      "ColorColumn",
    }
    for _, g in ipairs(groups) do
      vim.api.nvim_set_hl(0, g, { bg = "none" })
    end
    vim.api.nvim_set_hl(0, "TabLineFill", { bg = "none", fg = "#767676" })
  end
end

return M
