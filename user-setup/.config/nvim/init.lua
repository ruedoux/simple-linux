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
local fd_excludes_str = cfg._to_fd_exclude(cfg.hiddenPatterns)
local rg_excludes_str = cfg._to_rg_glob(cfg.hiddenPatterns)

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

-- Toggle hidden files (nvim-tree custom filter + fzf-lua)
local hiding_enabled = true

local function toggle_hidden_files()
  hiding_enabled = not hiding_enabled
  require("nvim-tree.api").filter.custom.toggle()
  vim.notify(
    hiding_enabled and "Hidden files: ON" or "Hidden files: OFF",
    hiding_enabled and vim.log.levels.INFO or vim.log.levels.WARN
  )
end

vim.keymap.set("n", "<leader>hh", toggle_hidden_files, { desc = "Toggle hidden files" })

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
  if hiding_enabled and fd_excludes_str ~= "" then
    require("fzf-lua").files({
      fd_opts = [[--color=never --type f --type l --exclude .git --exclude .jj]] .. fd_excludes_str,
    })
  else
    require("fzf-lua").files()
  end
end, { desc = "FZF Files" })
vim.keymap.set("n", "<leader>fg", function()
  if hiding_enabled and rg_excludes_str ~= "" then
    require("fzf-lua").live_grep({
      rg_opts = [[--column --line-number --no-heading --color=always --smart-case --max-columns=4096]] .. rg_excludes_str .. [[ -e]],
    })
  else
    require("fzf-lua").live_grep()
  end
end, { desc = "FZF Live Grep" })
vim.keymap.set("n", "<leader>fb", function()
  require("fzf-lua").buffers()
end, { desc = "FZF Buffers" })
vim.keymap.set("n", "<leader>fh", function()
  require("fzf-lua").help_tags()
end, { desc = "FZF Help Tags" })
vim.keymap.set("n", "<leader>fx", function()
  require("fzf-lua").diagnostics_document()
end, { desc = "FZF Diagnostics Document" })
vim.keymap.set("n", "<leader>fX", function()
  require("fzf-lua").diagnostics_workspace()
end, { desc = "FZF Diagnostics Workspace" })

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
