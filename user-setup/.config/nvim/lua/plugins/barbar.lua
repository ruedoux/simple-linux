local M = {}

function M.setup()
  require("barbar").setup({
    clickable = true,
    icons = {
      filetype = { enabled = true, custom_colors = false },
      buffer_index = false,
      buffer_number = false,
      button = "",
    },
  })
end

return M
