local M = {}

function M.setup()
  -- ============================================================================
  -- Movement
  -- ============================================================================

  -- better movement in wrapped text
  vim.keymap.set("n", "j", function()
    return vim.v.count == 0 and "gj" or "j"
  end, { expr = true, silent = true, desc = "Down (wrap-aware)" })
  vim.keymap.set("n", "k", function()
    return vim.v.count == 0 and "gk" or "k"
  end, { expr = true, silent = true, desc = "Up (wrap-aware)" })

  -- ============================================================================
  -- Search
  -- ============================================================================

  vim.keymap.set("n", "<leader>c", ":nohlsearch<CR>", { desc = "Clear search highlights" })

  vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result (centered)" })
  vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result (centered)" })
  vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
  vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })

  -- ============================================================================
  -- Editing
  -- ============================================================================

  vim.keymap.set("x", "<leader>p", '"_dP', { desc = "Paste without yanking" })
  vim.keymap.set({ "n", "v" }, "<leader>x", '"_d', { desc = "Delete without yanking" })

  vim.keymap.set("v", "<", "<gv", { desc = "Indent left and reselect" })
  vim.keymap.set("v", ">", ">gv", { desc = "Indent right and reselect" })

  vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines and keep cursor position" })

  vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down" })
  vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up" })
  vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
  vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

  vim.keymap.set("n", "<leader>pa", function()
    local path = vim.fn.expand("%:p")
    vim.fn.setreg("+", path)
    print("file:", path)
  end, { desc = "Copy full file path" })

  -- ============================================================================
  -- Buffers
  -- ============================================================================

  vim.keymap.set("n", "<leader>bn", ":bnext<CR>", { desc = "Next buffer" })
  vim.keymap.set("n", "<leader>bp", ":bprevious<CR>", { desc = "Previous buffer" })

  -- barbar.nvim buffer navigation
  vim.keymap.set("n", "<A-,>", "<Cmd>BufferPrevious<CR>", { desc = "Previous buffer" })
  vim.keymap.set("n", "<A-.>", "<Cmd>BufferNext<CR>", { desc = "Next buffer" })
  vim.keymap.set("n", "<A-c>", "<Cmd>BufferClose<CR>", { desc = "Close buffer" })
  vim.keymap.set("n", "<C-p>", "<Cmd>BufferPick<CR>", { desc = "Buffer picker" })

  -- ============================================================================
  -- Windows
  -- ============================================================================

  vim.keymap.set("n", "<leader>sv", ":vsplit<CR>", { desc = "Split window vertically" })
  vim.keymap.set("n", "<leader>sh", ":split<CR>", { desc = "Split window horizontally" })
  vim.keymap.set("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase window height" })
  vim.keymap.set("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease window height" })
  vim.keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width" })
  vim.keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width" })

  -- ============================================================================
  -- File explorer (nvim-tree)
  -- ============================================================================

  vim.keymap.set("n", "<leader>e", function()
    require("nvim-tree.api").tree.toggle()
  end, { desc = "Toggle NvimTree" })

  -- ============================================================================
  -- Search (fzf-lua)
  -- ============================================================================

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

  -- ============================================================================
  -- Git (mini.diff / mini.git)
  -- ============================================================================

  vim.keymap.set("n", "]h", function()
    require("mini.diff").goto_hunk("next")
  end, { desc = "Next git hunk" })
  vim.keymap.set("n", "[h", function()
    require("mini.diff").goto_hunk("prev")
  end, { desc = "Prev git hunk" })
  vim.keymap.set("n", "<leader>hs", function()
    require("mini.diff").operator()
  end, { desc = "Stage hunk" })
  vim.keymap.set("n", "<leader>hp", function()
    require("mini.diff").toggle_overlay()
  end, { desc = "Preview diff overlay" })
  vim.keymap.set("n", "<leader>hb", function()
    require("mini.git").show_at_cursor()
  end, { desc = "Git blame/show" })

  -- ============================================================================
  -- Markdown (render-markdown)
  -- ============================================================================

  vim.keymap.set("n", "<leader>tm", function()
    require("render-markdown").toggle()
  end, { desc = "Toggle markdown rendering" })

  -- ============================================================================
  -- Diagnostics
  -- ============================================================================

  vim.keymap.set("n", "<leader>td", function()
    vim.diagnostic.enable(not vim.diagnostic.is_enabled())
  end, { desc = "Toggle diagnostics" })
  vim.keymap.set("n", "<leader>q", function()
    vim.diagnostic.setloclist({ open = true })
  end, { desc = "Open diagnostic list" })
  vim.keymap.set("n", "<leader>dl", vim.diagnostic.open_float, { desc = "Show line diagnostics" })
end

return M
