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
  Iterator.builder({ node })
    :applier(function(n)
      if n.nodes then
        local toplevel = git.get_toplevel(n.cwd or n.link_to or n.absolute_path)
        explorer_module.reload(n, projects[toplevel] or {})
      end
    end)
    :recursor(function(n)
      return n.group_next and { n.group_next } or (n.open and n.nodes)
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
function M.reload_explorer()
  if event_running or not core.get_explorer() or vim.v.exiting ~= vim.NIL then
    return
  end
  event_running = true

  local projects = git.reload()
  refresh_nodes(core.get_explorer(), projects)
  if view.is_visible() then
    renderer.draw()
  end
  event_running = false
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NvimTreeReloaded",
  })
end

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

local throttle = throttle_discard(function(obj)
  refresh_nodes(core.get_explorer(), obj)
  if view.is_visible() then
    renderer.draw()
  end
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NvimTreeReloaded",
  })
end)

function M.reload_explorer_with_git()
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
    throttle(status)
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
