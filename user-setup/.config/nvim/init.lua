-- ============================================================================
-- Neovim configuration entry point
-- ============================================================================

-- Settings (edit config.lua to tweak)
local cfg = dofile(vim.fn.stdpath("config") .. "/config.lua")

-- Colorscheme + transparency
dofile(vim.fn.stdpath("config") .. "/colorscheme.lua").setup(cfg)

-- Apply all options from config
for k, v in pairs(cfg.options) do
  vim.opt[k] = v
end
for k, vals in pairs(cfg.option_appends) do
  for _, v in ipairs(vals) do
    vim.opt[k]:append(v)
  end
end
for k, v in pairs(cfg.globals) do
  vim.g[k] = v
end

-- Runtime paths and undo
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/site")

local undodir = vim.fn.expand("~/.vim/undodir")
if vim.fn.isdirectory(undodir) == 0 then
  vim.fn.mkdir(undodir, "p")
end
vim.opt.undodir = undodir

-- Statusline
dofile(vim.fn.stdpath("config") .. "/statusline.lua").setup()

-- Global keymaps
dofile(vim.fn.stdpath("config") .. "/keymaps.lua").setup()

-- Global autocmds
dofile(vim.fn.stdpath("config") .. "/autocmds.lua").setup()

-- Plugin sources (must be loaded before plugin configs)
dofile(vim.fn.stdpath("config") .. "/plugins.lua")

-- ============================================================================
-- PLUGIN CONFIGS
-- ============================================================================

-- Precompute hidden-file derived values
local hidden_vimregexes = vim.tbl_map(cfg._to_vimregex, cfg.hiddenPatterns)
-- Treesitter
dofile(vim.fn.stdpath("config") .. "/treesitter.lua").setup()

-- NvimTree
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
vim.keymap.set("n", "<leader>e", function()
  require("nvim-tree.api").tree.toggle()
end, { desc = "Toggle NvimTree" })

-- NvimTree transparency
vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = "none" })
vim.api.nvim_set_hl(0, "SignColumn", { bg = "none" })
vim.api.nvim_set_hl(0, "NvimTreeSignColumn", { bg = "none" })
vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = "none" })
vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = "#2a2a2a", bg = "none" })
vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { bg = "none" })

-- File pairs
dofile(vim.fn.stdpath("config") .. "/file-pairs.lua").setup({
  pairs = vim.tbl_map(function(s)
    return { suffix = s }
  end, cfg.pairedExtensions),
})

-- fzf-lua
require("fzf-lua").setup({})

vim.keymap.set("n", "<leader>ff", function()
  require("fzf-lua").files({ hidden = true, no_ignore = true })
end, { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", function()
    require("fzf-lua").live_grep({ rg_opts = "--no-ignore --hidden --glob '!.git'", silent = true })
end, { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", function()
  require("fzf-lua").buffers()
end, { desc = "Buffers" })
vim.keymap.set("n", "<leader>fh", function()
  require("fzf-lua").help_tags()
end, { desc = "Help tags" })
vim.keymap.set("n", "<leader>fx", function()
  require("fzf-lua").diagnostics_document()
end, { desc = "Document diagnostics" })
vim.keymap.set("n", "<leader>fX", function()
  require("fzf-lua").diagnostics_workspace()
end, { desc = "Workspace diagnostics" })

-- Quickfix replace helper (after fzf-lua grep → Ctrl+q → Enter)
vim.keymap.set("n", "<leader>fr", function()
  local from = vim.fn.input("Replace: ")
  if from == "" then return end
  local to = vim.fn.input("With: ")
  vim.cmd("cfdo %s/" .. from .. "/" .. to .. "/gc | update")
  vim.cmd("cclose")
end, { desc = "Replace in quickfix files" })

-- mini.nvim
require("mini.ai").setup({})
require("mini.comment").setup({})
require("mini.move").setup({})
require("mini.surround").setup({})
require("mini.cursorword").setup({})
require("mini.indentscope").setup({})
require("mini.pairs").setup({})
require("mini.trailspace").setup({})
require("mini.bufremove").setup({})
require("mini.notify").setup({})
require("mini.icons").setup({})

require("mini.diff").setup({
  view = {
    style = "sign",
    signs = { add = "▎", change = "▎", delete = "▎" },
  },
})

require("mini.git").setup({})

-- mini.diff keymaps
local MiniDiff = require("mini.diff")
vim.keymap.set("n", "]h", function()
  MiniDiff.goto_hunk("next")
end, { desc = "Next git hunk" })
vim.keymap.set("n", "[h", function()
  MiniDiff.goto_hunk("prev")
end, { desc = "Prev git hunk" })
vim.keymap.set("n", "<leader>hs", MiniDiff.operator, { desc = "Stage hunk" })
vim.keymap.set("n", "<leader>hp", function()
  MiniDiff.toggle_overlay()
end, { desc = "Preview diff overlay" })
vim.keymap.set("n", "<leader>hb", function()
  require("mini.git").show_at_cursor()
end, { desc = "Git blame/show" })

-- barbar.nvim tabline
require("barbar").setup({
  clickable = true,
  icons = {
    filetype = { enabled = true, custom_colors = false },
    buffer_index = false,
    buffer_number = false,
    button = "",
  },
})

-- LSP (includes Mason setup + auto-install)
dofile(vim.fn.stdpath("config") .. "/lsp.lua").setup()

-- Terminal
dofile(vim.fn.stdpath("config") .. "/terminal.lua").setup()
