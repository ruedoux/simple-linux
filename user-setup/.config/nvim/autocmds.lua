local M = {}

function M.setup()
  local augroup = vim.api.nvim_create_augroup("UserConfig", { clear = true })

  -- Format on save using attached LSP servers (real file buffers only)
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = augroup,
    pattern = {
      "*.lua",
      "*.py",
      "*.js",
      "*.jsx",
      "*.ts",
      "*.tsx",
      "*.json",
      "*.css",
      "*.scss",
      "*.html",
      "*.sh",
      "*.bash",
      "*.zsh",
      "*.c",
      "*.cs",
      "*.cpp",
      "*.h",
      "*.hpp",
    },
    callback = function(args)
      if vim.bo[args.buf].buftype ~= "" then return end
      if not vim.bo[args.buf].modifiable then return end
      if vim.api.nvim_buf_get_name(args.buf) == "" then return end

      pcall(vim.lsp.buf.format, {
        bufnr = args.buf,
        timeout_ms = 2000,
      })
    end,
  })

  -- highlight yanked text
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = augroup,
    callback = function()
      vim.hl.on_yank()
    end,
  })

  -- return to last cursor position
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    desc = "Restore last cursor position",
    callback = function()
      if vim.o.diff then
        return
      end

      local last_pos = vim.api.nvim_buf_get_mark(0, '"')
      local last_line = vim.api.nvim_buf_line_count(0)

      local row = last_pos[1]
      if row < 1 or row > last_line then
        return
      end

      pcall(vim.api.nvim_win_set_cursor, 0, last_pos)
    end,
  })

  -- wrap, linebreak and spellcheck on markdown and text files
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "markdown", "text", "gitcommit" },
    callback = function()
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
      vim.opt_local.spell = true
    end,
  })
end

return M
