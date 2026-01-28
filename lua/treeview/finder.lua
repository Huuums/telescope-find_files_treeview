local Path = require("plenary.path")
local finders = require("telescope.finders")
local utils = require("telescope.utils")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values

local scoring = require("treeview.scoring")

local M = {}

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local folder_icon = ""
local persistence_filename = "treeview.json"

local os_sep = Path.path.sep

local function normalize_cwd(cwd)
  if cwd then
    return utils.path_expand(cwd)
  end
  return vim.uv.cwd()
end

local function persistence_path(opts)
  if opts.persist_path then
    return opts.persist_path
  end
  return Path:new(vim.fn.stdpath("state"), persistence_filename):absolute()
end

local function load_persisted(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return {}
  end

  local content = table.concat(lines, "\n")
  local decoded = vim.json.decode(content)
  if type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

local function save_persisted(path, data)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local content = vim.json.encode(data)
  vim.fn.writefile({ content }, path)
end

local function get_find_command(opts)
  if opts.find_command then
    return vim.deepcopy(opts.find_command)
  end

  if vim.fn.executable("fd") == 1 then
    local cmd = { "fd", "--type", "f", "--strip-cwd-prefix" }
    if opts.hidden then
      table.insert(cmd, "--hidden")
    end
    if opts.no_ignore then
      table.insert(cmd, "--no-ignore")
    end
    if opts.no_ignore_parent then
      table.insert(cmd, "--no-ignore-parent")
    end
    if opts.follow then
      table.insert(cmd, "--follow")
    end
    if opts.search_dirs then
      vim.list_extend(cmd, opts.search_dirs)
    end
    return cmd
  end

  if vim.fn.executable("rg") == 1 then
    local cmd = { "rg", "--files", "--color", "never" }
    if opts.hidden then
      table.insert(cmd, "--hidden")
    end
    if opts.no_ignore then
      table.insert(cmd, "--no-ignore")
    end
    if opts.no_ignore_parent then
      table.insert(cmd, "--no-ignore-parent")
    end
    if opts.follow then
      table.insert(cmd, "--follow")
    end
    if opts.search_dirs then
      vim.list_extend(cmd, opts.search_dirs)
    end
    return cmd
  end

  utils.notify("treeview", {
    msg = "treeview requires fd or rg",
    level = "ERROR",
  })

  return nil
end

local function new_node(name, rel_path, abs_path, node_type, depth)
  return {
    name = name,
    rel_path = rel_path,
    path = abs_path,
    type = node_type,
    depth = depth,
    score = nil,
    children = {},
    _children_map = {},
  }
end

local function add_child(parent, child)
  parent._children_map[child.name] = child
  table.insert(parent.children, child)
end

local function ensure_child(parent, name, rel_path, abs_path, node_type)
  local existing = parent._children_map[name]
  if existing then
    return existing
  end

  local child = new_node(name, rel_path, abs_path, node_type, parent.depth + 1)
  add_child(parent, child)
  return child
end

local function collect_files(opts)
  local cwd = normalize_cwd(opts.cwd)
  local cmd = get_find_command(opts)
  if not cmd then
    return {}, cwd
  end

  local output = utils.get_os_command_output(cmd, cwd)
  local files = {}
  for _, entry in ipairs(output) do
    if entry ~= "" then
      table.insert(files, entry)
    end
  end
  return files, cwd
end

function M.build_tree(opts)
  opts = opts or {}
  local files, cwd = collect_files(opts)
  local root = new_node(".", "", cwd, "dir", 0)

  for _, rel in ipairs(files) do
    local rel_path = rel
    local abs_path

    if Path:new(rel_path):is_absolute() then
      abs_path = rel_path
      rel_path = Path:new(abs_path):make_relative(cwd)
    else
      abs_path = Path:new(cwd, rel_path):absolute()
    end

    local parts = vim.split(rel_path, os_sep, { plain = true, trimempty = true })
    local current = root
    local current_rel = ""

    for index, part in ipairs(parts) do
      current_rel = current_rel == "" and part or (current_rel .. os_sep .. part)
      local is_file = index == #parts
      local node_type = is_file and "file" or "dir"
      local node_abs = is_file and abs_path or Path:new(cwd, current_rel):absolute()
      current = ensure_child(current, part, current_rel, node_abs, node_type)
    end
  end

  return root, cwd
end

local function should_include(node, query)
  if query == "" then
    return true
  end
  return node.score ~= nil
end

local function sort_children(children)
  local sorted = {}
  for i, child in ipairs(children) do
    sorted[i] = child
  end

  table.sort(sorted, function(a, b)
    if a.type ~= b.type then
      return a.type == "dir"
    end
    local score_a = a.score or -math.huge
    local score_b = b.score or -math.huge
    if score_a ~= score_b then
      return score_a > score_b
    end
    return a.name < b.name
  end)

  return sorted
end

local function get_icon_for_entry(entry, icons_enabled)
  if not icons_enabled then
    return nil
  end

  if entry.type == "dir" then
    return folder_icon
  end

  if not has_devicons then
    return nil
  end

  local icon = devicons.get_icon(entry.name, nil, { default = true })
  return icon
end

local function is_expanded(state, node, query)
  if node.type ~= "dir" then
    return true
  end
  if query ~= "" and node.score ~= nil then
    return true
  end
  local value = state.expanded[node.path]
  if value == nil then
    return true
  end
  return value
end

local function flatten_tree(state, query)
  local root = state.root
  local icons_enabled = state.icons_enabled
  local entries = {}
  local function walk(node, prefix, is_last)
    if node ~= root then
      if not should_include(node, query) then
        return
      end
      local branch = is_last and "└─ " or "├─ "
      local suffix = node.type == "dir" and "/" or ""
      local icon = get_icon_for_entry(node, icons_enabled)
      local icon_prefix = icon and (icon .. " ") or ""
      local display = prefix .. branch .. icon_prefix .. node.name .. suffix
      table.insert(entries, {
        node = node,
        display = display,
        ordinal = node.rel_path,
        path = node.path,
        type = node.type,
      })
    end

    if node.type == "dir" and not is_expanded(state, node, query) then
      return
    end

    local next_prefix = prefix .. (is_last and "   " or "│  ")
    local children = node.children
    if query ~= "" then
      children = sort_children(node.children)
    end

    for i, child in ipairs(children) do
      walk(child, next_prefix, i == #children)
    end
  end

  for i, child in ipairs(root.children) do
    walk(child, "", i == #root.children)
  end

  return entries
end

local function first_file_index(entries)
  for i, entry in ipairs(entries) do
    if entry.type == "file" then
      return i
    end
  end
  return nil
end

function M.entries_for_prompt(state, prompt)
  local query = prompt or ""
  scoring.score_tree(state.root, query)
  return flatten_tree(state, query)
end

function M.new_state(root, opts)
  opts = opts or {}
  local icons_enabled = opts.icons
  if icons_enabled == nil then
    icons_enabled = has_devicons
  end
  local persist_enabled = opts.persist
  if persist_enabled == nil then
    persist_enabled = true
  end
  local cwd = normalize_cwd(opts.cwd)
  local persist_path = persistence_path(opts)
  local persisted = persist_enabled and load_persisted(persist_path) or {}
  local expanded = {}
  if type(persisted[cwd]) == "table" then
    expanded = persisted[cwd]
  end
  return {
    root = root,
    prompt = nil,
    entries = nil,
    first_file_index = nil,
    icons_enabled = icons_enabled,
    expanded = expanded,
    persist_enabled = persist_enabled,
    persist_path = persist_path,
    persist_key = cwd,
  }
end

function M.update_state(state, prompt)
  if state.prompt == prompt and state.entries then
    return state.entries, state.first_file_index
  end

  local entries = M.entries_for_prompt(state, prompt)
  local index = first_file_index(entries)

  state.prompt = prompt
  state.entries = entries
  state.first_file_index = index

  return entries, index
end

function M.toggle_node(state, node)
  if not node or node.type ~= "dir" then
    return false
  end
  local current = is_expanded(state, node)
  state.expanded[node.path] = not current
  state.prompt = nil
  state.entries = nil
  state.first_file_index = nil
  M.persist_state(state)
  return true
end

function M.set_node_expanded(state, node, expanded)
  if not node or node.type ~= "dir" then
    return false
  end
  state.expanded[node.path] = expanded
  state.prompt = nil
  state.entries = nil
  state.first_file_index = nil
  M.persist_state(state)
  return true
end

local function walk_dirs(node, cb)
  if node.type == "dir" then
    cb(node)
  end
  for _, child in ipairs(node.children) do
    walk_dirs(child, cb)
  end
end

function M.get_top_level_dir(state, node)
  if not node or not node.rel_path or node.rel_path == "" then
    return nil
  end
  local parts = vim.split(node.rel_path, os_sep, { plain = true, trimempty = true })
  local top = parts[1]
  if not top or top == "" then
    return nil
  end
  return state.root._children_map[top]
end

function M.set_all_expanded(state, expanded)
  walk_dirs(state.root, function(node)
    state.expanded[node.path] = expanded
  end)
  state.prompt = nil
  state.entries = nil
  state.first_file_index = nil
  M.persist_state(state)
end

function M.persist_state(state)
  if not state.persist_enabled then
    return
  end
  local data = load_persisted(state.persist_path)
  data[state.persist_key] = state.expanded
  save_persisted(state.persist_path, data)
end

function M.entry_maker()
  return function(entry)
    return {
      value = entry.node,
      display = entry.display,
      ordinal = entry.ordinal,
      path = entry.path,
      type = entry.type,
    }
  end
end

function M.finder(state)
  return finders.new_dynamic {
    fn = function(prompt)
      local entries = M.update_state(state, prompt)
      return entries
    end,
    entry_maker = M.entry_maker(),
  }
end

function M.previewer()
  return previewers.new_buffer_previewer {
    title = "Preview",
    define_preview = function(self, entry)
      if entry.type ~= "file" or not entry.path then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {})
        return
      end
      conf.buffer_previewer_maker(entry.path, self.state.bufnr, {
        winid = self.state.winid,
        bufname = self.state.bufname,
      })
    end,
  }
end

return M
