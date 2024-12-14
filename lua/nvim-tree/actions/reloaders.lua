local git = require "nvim-tree.git"
local git_utils = require "nvim-tree.git.utils"
local view = require "nvim-tree.view"
local renderer = require "nvim-tree.renderer"
local explorer_module = require "nvim-tree.explorer"
local core = require "nvim-tree.core"
local explorer_node = require "nvim-tree.explorer.node"
local Iterator = require "nvim-tree.iterators.node-iterator"

local M = {}

-- ... (previous code)

-- Instead of running 'wc -l' here, we:
-- 1. Define a function that returns the count file path based on cwd.
-- 2. Check if the file exists.
-- 3. If not, generate it by invoking the external shell command once.
-- 4. Parse the file line-by-line to get counts.
-- 5. Assign counts to the nodes.

local function get_count_file_path()
  local cwd = vim.uv.cwd()
  -- Transform the absolute path into a filename by replacing `/` with `_`
  local safe_cwd = cwd:gsub("/", "_")
  local count_file = "/Users/xzb/.config/nvim/.count/" .. safe_cwd .. ".txt"
  return count_file
end

local function file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

local function generate_line_count_file(cwd, files)
  -- Build the shell command equivalent to what was previously discussed.
  -- Using fd + xargs might not be ideal here since we already have `files_to_count`.
  -- Instead, just replicate logic: run wc -l on all files and store the output.
  -- For simplicity, we rely on 'sh' and 'printf' to handle arguments safely.
  -- Note: Ensure that you have 'sh', 'wc' available.
  local cmd = { "sh", "/Users/xzb/.config/nvim/tree.sh" }
  vim.system(cmd, nil, function(out)
    vim.cmd "NvimTreeRefresh"
  end)
end

local function load_line_counts(count_file)
  local path_to_count = {}
  local f = io.open(count_file, "r")
  if f then
    for line in f:lines() do
      if not line:find " total" then
        local count, path = line:match "^%s*(%d+)%s+(.*)$"
        if count and path then
          path_to_count[path] = tonumber(count)
        end
      end
    end
    f:close()
  end
  return path_to_count
end

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
  local path_to_count = {}
  if vim.g.show_nvim_tree_size then
    local count_file = get_count_file_path()
    if not file_exists(count_file) then
      local cmd = { "sh", "/Users/xzb/.config/nvim/tree.sh" }
      vim.defer_fn(function()
        vim.system(cmd, nil, function() end)
      end, 200)
    else
      path_to_count = load_line_counts(count_file)
    end
  end
  Iterator.builder({ node })
    :applier(function(n)
      if n.nodes then
        local toplevel = git.get_toplevel(n.cwd or n.link_to or n.absolute_path)
        explorer_module.reload(n, projects[toplevel] or {}, path_to_count)
      end
    end)
    :recursor(function(n)
      if vim.g.show_nvim_tree_size then
        return n.group_next and { n.group_next } or n.nodes
      else
        return n.group_next and { n.group_next } or (n.open and n.nodes)
      end
    end)
    :iterate()

  local top_node = node
  local function sum_line_counts(node)
    if node ~= top_node and node.type ~= "directory" then
      return node.line_count or 0
    end

    -- If it's a directory, recursively sum all children
    local total = 0
    for _, child in ipairs(node.nodes) do
      total = total + sum_line_counts(child)
    end
    node.line_count = total
    return total
  end
  if vim.g.show_nvim_tree_size then
    sum_line_counts(node)
    Iterator.builder({ node })
      :applier(function(n)
        if n.nodes then
          require("nvim-tree.explorer.sorters").sort(n.nodes)
        end
      end)
      :recursor(function(n)
        return n.group_next and { n.group_next } or n.nodes
      end)
      :iterate()
  end
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

_G.event_running = false
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

local throttle = function(obj, callback)
  refresh_nodes(core.get_explorer(), obj)
  if view.is_visible() then
    renderer.draw()
  end
  if callback ~= nil then
    callback()
  end
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NvimTreeReloaded",
  })
end

function M.reload_explorer(callback)
  if _G.event_running or not core.get_explorer() or vim.v.exiting ~= vim.NIL then
    return
  end
  _G.event_running = true
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
    _G.event_running = false
  end)
end

function M.reload_git()
  if not core.get_explorer() or not git.config.git.enable or _G.event_running then
    return
  end
  _G.event_running = true

  local projects = git.reload()
  M.reload_node_status(core.get_explorer(), projects)
  renderer.draw()
  _G.event_running = false
end

return M
