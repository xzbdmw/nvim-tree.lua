local lib = require "nvim-tree.lib"
local utils = require "nvim-tree.utils"
local filters = require "nvim-tree.explorer.filters"
local reloaders = require "nvim-tree.actions.reloaders"

local M = {}

local function set_cursor_first_dirty_file(callback)
  local winid = require("nvim-tree.api").tree.winid()
  if winid == nil or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(winid)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first_file_index
  local fname = vim.fs.basename(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
  for _, line in ipairs(lines) do
    if vim.endswith(line, "~") then
      if string.find(line, fname, nil, true) ~= nil then
        return
      end
    end
  end
  for i, line in ipairs(lines) do
    if i == 1 then
      goto continue
    end
    if string.find(line, "~", nil, true) ~= nil then
      first_file_index = i
      break
    end
    ::continue::
  end
  if first_file_index == nil then
    return
  end
  vim.api.nvim_win_set_cursor(winid, { first_file_index, 0 })
  vim.g.found = false
  require("nvim-tree.api").tree.find_file()
  if vim.g.found == false then
    require("nvim-tree.api").node.open.edit()
  end
  callback()
end

local function reload(callback)
  reloaders.reload_explorer(function()
    vim.schedule(function()
      set_cursor_first_dirty_file()
    end)
    if callback ~= nil then
      callback()
    end
  end)
end

local function reload_git(callback)
  reloaders.reload_explorer(function()
    vim.schedule(function()
      set_cursor_first_dirty_file(callback)
    end)
  end)
end

function M.custom()
  filters.config.filter_custom = not filters.config.filter_custom
  reload()
end

function M.git_ignored()
  filters.config.filter_git_ignored = not filters.config.filter_git_ignored
  reload()
end

function M.git_clean()
  filters.config.filter_git_clean = not filters.config.filter_git_clean
  reload_git(function()
    if filters.config.filter_git_clean == true then
      vim.schedule(function()
        require("config.utils").gitsign_try_nav_first()
        FeedKeys("z", "m")
      end)
    end
  end)
end

function M.no_buffer()
  filters.config.filter_no_buffer = not filters.config.filter_no_buffer
  reload()
end

function M.no_arrow()
  filters.config.filter_no_arrow = not filters.config.filter_no_arrow
  reload()
end

function M.no_bookmark()
  filters.config.filter_no_bookmark = not filters.config.filter_no_bookmark
  reload()
end

function M.dotfiles()
  filters.config.filter_dotfiles = not filters.config.filter_dotfiles
  reload()
end

function M.enable()
  filters.config.enable = not filters.config.enable
  reload()
end

return M
