local git = require "nvim-tree.git"
local git_utils = require "nvim-tree.git.utils"
local view = require "nvim-tree.view"
local renderer = require "nvim-tree.renderer"
local explorer_module = require "nvim-tree.explorer"
local core = require "nvim-tree.core"
local explorer_node = require "nvim-tree.explorer.node"
local Iterator = require "nvim-tree.iterators.node-iterator"

local M = {}

---@param node Explorer|nil
---@param projects table
local function refresh_nodes(node, projects)
  local has_git_status_item = false
  for _, p in pairs(projects) do
    for f, v in pairs(p.files) do
      if v ~= "!!" then
        has_git_status_item = true
        break
      end
    end
  end
  if not has_git_status_item and require("nvim-tree.explorer.filters").config.filter_git_clean then
    vim.notify("", vim.log.levels.INFO, { title = "No Changed File" })
    require("nvim-tree.explorer.filters").config.filter_git_clean = false
  end
  Iterator.builder({ node })
    :applier(function(n)
      if n.nodes then
        local toplevel = git.get_toplevel(n.cwd or n.link_to or n.absolute_path)
        explorer_module.reload(n, projects[toplevel] or {})
      end
    end)
    :recursor(function(n)
      -- expand all git dirty dirs
      if require("nvim-tree.explorer.filters").config.filter_git_clean then
        return n.group_next and { n.group_next } or n.nodes
      else
        return n.group_next and { n.group_next } or (n.open and n.nodes)
      end
    end)
    :iterate()
end

---@param parent_node Node|nil
---@param projects table
function M.reload_node_status(parent_node, projects)
  if parent_node == nil then
    return
  end

  local toplevel = git.get_toplevel(parent_node.absolute_path)
  local status = projects[toplevel] or {}
  for _, node in ipairs(parent_node.nodes) do
    explorer_node.update_git_status(node, explorer_node.is_git_ignored(parent_node), status)
    if node.nodes and #node.nodes > 0 then
      M.reload_node_status(node, projects)
    end
  end
end

local event_running = false

--- @generic F: function
--- @param f F
--- @param ms? number
--- @return F
local function throttle_discard(f, ms)
  ms = ms or 200
  local timer = assert(vim.loop.new_timer())
  local is_running = false
  return function(...)
    if is_running then
      return
    end
    is_running = true
    f(...)
    timer:start(ms, 0, function()
      is_running = false
    end)
  end
end

local throttle = throttle_discard(function(obj, callback)
  refresh_nodes(core.get_explorer(), obj)
  if view.is_visible() then
    renderer.draw()
  end
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NvimTreeReloaded",
  })
  if callback ~= nil then
    callback()
  end
end)

function M.reload_explorer(callback)
  if event_running or not core.get_explorer() or vim.v.exiting ~= vim.NIL then
    return
  end
  event_running = true
  local cwd = vim.loop.cwd()
  git.reload(function(output)
    local new_cwd = vim.loop.cwd()
    local status = {}
    status[cwd] = {
      files = output,
      dirs = git_utils.file_status_to_dir_status(output, cwd),
      watcher = nil,
    }
    throttle(status, callback)
    event_running = false
  end)
end

function M.reload_git()
  if not core.get_explorer() or not git.config.git.enable or event_running then
    return
  end
  event_running = true

  local projects = git.reload()
  M.reload_node_status(core.get_explorer(), projects)
  renderer.draw()
  event_running = false
end

return M
