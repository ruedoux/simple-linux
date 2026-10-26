-- ============================================================================
-- Neovim configuration entry point.
--
-- Loads settings, then delegates each concern to its own module under lua/.
-- Order matters: plugin sources must be registered before any plugin config.
-- ============================================================================

local config = require("config")

require("colorscheme").setup(config)
require("options").setup(config)
require("statusline").setup()
require("keymaps").setup()
require("autocmds").setup()

require("plugins.sources").setup()

require("plugins.treesitter").setup()
require("plugins.nvim-tree").setup(config)
require("file-pairs").setup(config)
require("plugins.fzf-lua").setup()
require("plugins.mini").setup()
require("plugins.render-markdown").setup()
require("plugins.barbar").setup()
require("plugins.lsp").setup()

require("terminal").setup()
