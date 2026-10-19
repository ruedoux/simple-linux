local M = {}

local terminal_state = {
  buf = nil,
  win = nil,
  code_win = nil,
  is_open = false,
  root = nil,
  root_cwd = nil,
}

local function get_project_root()
  local cwd = vim.fn.getcwd()
  if terminal_state.root_cwd == cwd and terminal_state.root then
    return terminal_state.root
  end

  local root = cwd
  local ok, git_root = pcall(vim.fn.system, { "git", "rev-parse", "--show-toplevel" })
  if ok and vim.v.shell_error == 0 and git_root then
    git_root = vim.trim(git_root)
    if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
      root = git_root
    end
  end

  terminal_state.root_cwd = cwd
  terminal_state.root = root
  return root
end

local function is_open()
  return terminal_state.is_open
    and terminal_state.win
    and vim.api.nvim_win_is_valid(terminal_state.win)
end

local function ensure_terminal_buf()
  if terminal_state.buf and vim.api.nvim_buf_is_valid(terminal_state.buf) then
    return
  end
  terminal_state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[terminal_state.buf].bufhidden = "hide"
end

local function start_shell()
  if vim.bo[terminal_state.buf].buftype == "terminal" then
    return
  end
  local root = get_project_root()
  vim.fn.termopen(os.getenv("SHELL"), { cwd = root })
end

local function apply_terminal_border(win)
  vim.api.nvim_set_hl(0, "TerminalBorder", { fg = "#444444", bg = "none" })
  vim.wo[win].winbar = "%#TerminalBorder#%{repeat('─', &columns)}"
  vim.wo[win].statusline = "%#TerminalBorder#%{repeat('─', &columns)}"
end

local function close()
  if not is_open() then
    terminal_state.is_open = false
    return
  end
  if terminal_state.code_win and vim.api.nvim_win_is_valid(terminal_state.code_win) then
    vim.api.nvim_set_current_win(terminal_state.code_win)
  end
  vim.api.nvim_win_close(terminal_state.win, false)
  terminal_state.is_open = false
  terminal_state.win = nil
end

local function open()
  if is_open() then
    vim.api.nvim_set_current_win(terminal_state.win)
    return
  end

  ensure_terminal_buf()

  terminal_state.code_win = vim.api.nvim_get_current_win()

  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, terminal_state.buf)
  vim.api.nvim_win_set_height(win, math.floor(vim.o.lines * 0.3))
  apply_terminal_border(win)

  terminal_state.win = win
  terminal_state.is_open = true

  start_shell()

  vim.cmd("startinsert")
end

local function toggle()
  if is_open() then
    close()
    return
  end
  open()
end

function M.setup()
  local augroup = vim.api.nvim_create_augroup("TerminalConfig", { clear = true })

  vim.api.nvim_create_autocmd("TermClose", {
    group = augroup,
    callback = function()
      if vim.v.event.status == 0 then
        local buf = terminal_state.buf
        terminal_state.buf = nil
        terminal_state.is_open = false
        terminal_state.win = nil
        if buf and vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, {})
        end
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

  vim.keymap.set("n", "<leader>t", toggle, { noremap = true, silent = true, desc = "Toggle bottom terminal" })
  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { noremap = true, silent = true, desc = "Terminal normal mode" })
  vim.keymap.set("t", "<C-q>", close, { noremap = true, silent = true, desc = "Close bottom terminal" })
end

return M
