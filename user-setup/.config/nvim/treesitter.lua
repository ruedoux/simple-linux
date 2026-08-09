local M = {}

function M.setup()
  local has_cc = vim.fn.executable("cc") == 1 or vim.fn.executable("gcc") == 1
  if not has_cc then
    vim.schedule(function()
      vim.notify(
        "[treesitter] No C compiler found (gcc/cc missing). "
          .. "Install with: sudo pacman -S gcc\n"
          .. "Then run :TSEnsure to install parsers.",
        vim.log.levels.WARN
      )
    end)
  end

  local treesitter = require("nvim-treesitter")
  treesitter.setup({})

  local ensure_installed = {
    "bash", "c", "cpp", "c_sharp", "css", "html", "json",
    "lua", "markdown", "markdown_inline", "python", "rust", "vim", "vimdoc",
  }

  local ts_config = require("nvim-treesitter.config")
  local installed = ts_config.get_installed()
  local missing = {}
  for _, parser in ipairs(ensure_installed) do
    if not vim.tbl_contains(installed, parser) then
      table.insert(missing, parser)
    end
  end
  if #missing > 0 then
    treesitter.install(missing)
  end

  vim.api.nvim_create_user_command("TSEnsure", function()
    local current = ts_config.get_installed()
    local need = {}
    for _, parser in ipairs(ensure_installed) do
      if not vim.tbl_contains(current, parser) then
        table.insert(need, parser)
      end
    end
    if #need == 0 then
      vim.notify("[treesitter] All parsers installed", vim.log.levels.INFO)
    else
      vim.notify("[treesitter] Installing: " .. table.concat(need, ", "), vim.log.levels.INFO)
      treesitter.install(need)
    end
  end, {})
end

return M
