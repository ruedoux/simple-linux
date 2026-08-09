-- Centralized Neovim configuration.
-- Tweak everything here instead of hunting through init.lua.

return {
  -- ============================================================================
  -- Editor preferences
  -- ============================================================================

  -- Colorscheme and transparency
  colorscheme = "habamax",
  transparent = true,

  -- Options (vim.opt)
  options = {
    -- Appearance
    number = true,             -- absolute line numbers
    relativenumber = true,     -- relative line numbers
    cursorline = true,         -- highlight current line
    wrap = false,              -- don't wrap long lines
    signcolumn = "yes",        -- always show the sign column
    colorcolumn = "100",       -- ruler at column 100
    fillchars = { eob = " " }, -- hide "~" on empty lines
    showmode = false,          -- mode shown in statusline, not command line
    showtabline = 2,           -- always show tabline (for barbar.nvim)
    showmatch = true,          -- highlight matching brackets
    guicursor =
    "n-v-c:block,i-ci-ve:block,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175",
    conceallevel = 2,          -- hide concealed text (Obsidian)
    concealcursor = "",        -- don't hide cursor line in markup
    synmaxcol = 300,           -- max column for syntax highlighting
    winblend = 0,              -- no floating window transparency

    -- Scrolling
    scrolloff = 10,     -- keep 10 lines above/below cursor
    sidescrolloff = 10, -- keep 10 columns left/right of cursor

    -- Indentation
    tabstop = 2,        -- tab width
    shiftwidth = 2,     -- indent width
    softtabstop = 2,    -- soft tab stop (tab/backspace)
    expandtab = true,   -- spaces instead of tabs
    smartindent = true, -- smart auto-indent
    autoindent = true,  -- copy indent from current line

    -- Search
    ignorecase = true, -- case-insensitive search
    smartcase = true,  -- case-sensitive when uppercase used
    hlsearch = true,   -- highlight all search matches
    incsearch = true,  -- show matches as you type

    -- Completion
    completeopt = "menuone,noinsert,noselect",
    pumheight = 10, -- max popup menu height
    pumblend = 10,  -- popup menu transparency

    -- Command line
    cmdheight = 1,                  -- command line height
    wildmenu = true,                -- tab completion menu
    wildmode = "longest:full,full", -- complete longest match, full list, cycle

    -- Files and buffers
    backup = false,      -- no backup files
    writebackup = false, -- no backup on write
    swapfile = false,    -- no swap files
    undofile = true,     -- persistent undo
    autoread = true,     -- auto-reload when file changes externally
    autowrite = false,   -- don't auto-save
    hidden = true,       -- allow hidden (modified) buffers

    -- Editing
    errorbells = false,             -- no error sounds
    backspace = "indent,eol,start", -- sensible backspace behavior
    selection = "inclusive",        -- include last char in selection
    mouse = "a",                    -- enable mouse in all modes
    modifiable = true,              -- allow buffer modifications
    autochdir = false,              -- don't auto-change directory

    -- Splits
    splitbelow = true, -- horizontal splits go below
    splitright = true, -- vertical splits go right

    -- Timing
    updatetime = 300, -- faster swap/trigger interval
    timeoutlen = 500, -- mapping timeout
    ttimeoutlen = 50, -- key code timeout

    -- Folding (requires treesitter)
    foldmethod = "expr",                          -- expression-based folding
    foldexpr = "v:lua.vim.treesitter.foldexpr()", -- treesitter fold expression
    foldlevel = 99,                               -- start with all folds open

    -- Performance
    redrawtime = 10000,    -- redraw timeout (helps with large files)
    maxmempattern = 20000, -- max memory for pattern matching
  },

  -- Append operations (vim.opt.xxx:append("value"))
  option_appends = {
    path = { "**" },               -- search subdirectories
    iskeyword = { "-" },           -- treat hyphens as word chars
    clipboard = { "unnamedplus" }, -- use system clipboard
    diffopt = { "linematch:60" },  -- improve diff alignment
  },

  -- Global variables (vim.g)
  globals = {
    mapleader = " ",           -- leader key (space)
    maplocalleader = " ",      -- local leader key (space)
    barbar_auto_setup = false, -- manual barbar setup
  },

  -- ============================================================================
  -- Project-specific file settings
  -- ============================================================================
  pairedExtensions = { ".import", ".uid" },
  hiddenPatterns = { "*.uid", "*.import" },

  -- ============================================================================
  -- Hidden-file helpers (derived from hiddenPatterns above)
  -- ============================================================================

  -- Convert a glob pattern to vim regex for nvim-tree filters.custom
  _to_vimregex = function(pattern)
    if vim.startswith(pattern, "*") then
      return vim.fn.escape(pattern:sub(2), ".*^$~\\/[]") .. "$"
    end
    return vim.fn.escape(pattern, ".*^$~\\/[]")
  end,

  -- Build --exclude flags for fd
  _to_fd_exclude = function(patterns)
    if #patterns == 0 then return "" end
    return " " .. table.concat(vim.tbl_map(function(p)
      return "--exclude '" .. p .. "'"
    end, patterns), " ")
  end,

  -- Build -g exclude flags for rg
  _to_rg_glob = function(patterns)
    if #patterns == 0 then return "" end
    return " " .. table.concat(vim.tbl_map(function(p)
      return "-g '!" .. p .. "'"
    end, patterns), " ")
  end,
}
