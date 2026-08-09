local M = {}

local config = { pairs = {} }
M._deleting = {}

function M._find_pair(path)
  for _, pair in ipairs(config.pairs) do
    local s = pair.suffix
    if path:sub(-#s) == s then return path:sub(1, -(#s + 1)) end
    local with_s = path .. s
    if vim.uv.fs_stat(with_s) then return with_s end
  end
end

function M._compute_new_pair(old_path, new_path, old_pair)
  for _, pair in ipairs(config.pairs) do
    local s = pair.suffix
    if old_path .. s == old_pair then return new_path .. s end
    if old_path:sub(-#s) == s then return new_path:sub(1, -(#s + 1)) end
  end
end

function M._on_will_rename(old_path, new_path)
  local pair = M._find_pair(old_path)
  if not pair or not vim.uv.fs_stat(pair) then return end
  local new_pair = M._compute_new_pair(old_path, new_path, pair)
  if new_pair then vim.uv.fs_rename(pair, new_pair) end
end

function M._on_will_remove(path)
  if M._deleting[path] then return end
  local pair = M._find_pair(path)
  if not pair or not vim.uv.fs_stat(pair) then return end
  M._deleting[pair] = true
  vim.uv.fs_unlink(pair)
  M._deleting[pair] = nil
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  local events = require("nvim-tree.api").events
  events.subscribe(events.Event.WillRenameNode, function(p)
    M._on_will_rename(p.old_name, p.new_name)
  end)
  events.subscribe(events.Event.WillRemoveFile, function(p)
    M._on_will_remove(p.fname)
  end)
end

return M
