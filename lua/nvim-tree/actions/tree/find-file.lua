local core = require "nvim-tree.core"
local lib = require "nvim-tree.lib"
local view = require "nvim-tree.view"
local finders_find_file = require "nvim-tree.actions.finders.find-file"

local M = {}

--- Find file or buffer
---@param opts ApiTreeFindFileOpts|nil|boolean legacy -> opts.buf
function M.fn(opts)
  -- legacy arguments
  if type(opts) == "string" then
    opts = {
      buf = opts,
    }
  end
  opts = opts or {}

  -- do nothing if closed and open not requested
  if not opts.open and not core.get_explorer() then
    return
  end

  local bufnr, path

  -- (optional) buffer number and path
  if type(opts.buf) == "nil" then
    bufnr = vim.api.nvim_get_current_buf()
    path = vim.api.nvim_buf_get_name(bufnr)
  elseif type(opts.buf) == "number" then
    if not vim.api.nvim_buf_is_valid(opts.buf) then
      return
    end
    bufnr = tonumber(opts.buf)
    path = vim.api.nvim_buf_get_name(bufnr)
  elseif type(opts.buf) == "string" then
    bufnr = nil
    path = tostring(opts.buf)
  else
    return
  end
  local cursor_abs_path = lib.get_node_at_cursor() ~= nil and lib.get_node_at_cursor().absolute_path or ""
  if cursor_abs_path == path then
    return
  end

  -- if require("nvim-tree.explorer.filters").config.filter_git_clean then
  --   local pass = false
  --   local projects = require("nvim-tree.git").get_project(vim.loop.cwd()) or {}
  --   -- __AUTO_GENERATED_PRINT_VAR_START__
  --   print([==[M.fn#if projects:]==], vim.inspect(projects)) -- __AUTO_GENERATED_PRINT_VAR_END__
  --   if projects.dirs ~= nil then
  --     for f, v in pairs(projects.files) do
  --       -- __AUTO_GENERATED_PRINT_VAR_START__
  --       print([==[M.fn#if#if#for f:]==], vim.inspect(f)) -- __AUTO_GENERATED_PRINT_VAR_END__
  --       -- __AUTO_GENERATED_PRINT_VAR_START__
  --       print([==[M.fn#if#if#for#if path:]==], vim.inspect(path)) -- __AUTO_GENERATED_PRINT_VAR_END__
  --       if path == f then
  --         pass = true
  --         break
  --       end
  --     end
  --   end
  --   -- __AUTO_GENERATED_PRINT_VAR_START__
  --   print([==[M.fn#if#if pass:]==], vim.inspect(pass)) -- __AUTO_GENERATED_PRINT_VAR_END__
  --   if not pass then
  --     return
  --   end
  -- end

  if view.is_visible() then
    -- focus
    if opts.focus then
      lib.set_target_win()
      view.focus()
    end
  elseif opts.open then
    -- open
    lib.open { current_window = opts.current_window, winid = opts.winid }
    if not opts.focus then
      vim.cmd "noautocmd wincmd p"
    end
  end

  -- update root
  if opts.update_root or M.config.update_focused_file.update_root.enable then
    require("nvim-tree").change_root(path, bufnr)
  end

  -- find
  finders_find_file.fn(path)
end

function M.setup(opts)
  M.config = opts or {}
end

return M
