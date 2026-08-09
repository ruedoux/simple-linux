local M = {}

local terminal_state = { buf = nil, win = nil, is_open = false }

function M.setup()
  local augroup = vim.api.nvim_create_augroup("TerminalConfig", { clear = true })

  vim.api.nvim_create_autocmd("TermClose", {
    group = augroup,
    callback = function()
      if vim.v.event.status == 0 then
        vim.api.nvim_buf_delete(0, {})
      end
    end,
  })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = augroup,
    callback = function()
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.signcolumn = "no"
    end,
  })

  local function toggle()
    if terminal_state.is_open and terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
      vim.api.nvim_win_close(terminal_state.win, false)
      terminal_state.is_open = false
      return
    end

    if not terminal_state.buf or not vim.api.nvim_buf_is_valid(terminal_state.buf) then
      terminal_state.buf = vim.api.nvim_create_buf(false, true)
      vim.bo[terminal_state.buf].bufhidden = "hide"
    end

    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    terminal_state.win = vim.api.nvim_open_win(terminal_state.buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
    })

    vim.wo[terminal_state.win].winblend = 0
    vim.wo[terminal_state.win].winhighlight = "Normal:FloatingTermNormal,FloatBorder:FloatingTermBorder"
    vim.api.nvim_set_hl(0, "FloatingTermNormal", { bg = "none" })
    vim.api.nvim_set_hl(0, "FloatingTermBorder", { bg = "none" })

    if vim.bo[terminal_state.buf].buftype ~= "terminal" then
      vim.fn.termopen(os.getenv("SHELL"))
    end

    terminal_state.is_open = true
    vim.cmd("startinsert")

    local term_augroup = vim.api.nvim_create_augroup("FloatingTermLeave_" .. terminal_state.win, { clear = true })
    vim.api.nvim_create_autocmd("BufLeave", {
      group = term_augroup,
      buffer = terminal_state.buf,
      callback = function()
        if terminal_state.is_open and terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
          vim.api.nvim_win_close(terminal_state.win, false)
          terminal_state.is_open = false
        end
      end,
      once = true,
    })
  end

  vim.keymap.set("n", "<leader>t", toggle, { noremap = true, silent = true, desc = "Toggle floating terminal" })
  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { noremap = true, silent = true, desc = "Terminal normal mode" })
  vim.keymap.set("t", "<C-q>", function()
    if terminal_state.is_open and terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
      vim.api.nvim_win_close(terminal_state.win, false)
      terminal_state.is_open = false
    end
  end, { noremap = true, silent = true, desc = "Close floating terminal" })
end

return M
