local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local finder = require("treeview.finder")

local M = {}

M.config = {}

function M.setup(opts)
  M.config = opts or {}
end

local function find_entry_index(entries, selected)
  if not selected then
    return nil
  end
  for i, entry in ipairs(entries) do
    if entry.node == selected.value then
      return i
    end
  end
  return nil
end

local function find_next_file_index(entries, start_index, direction)
  if #entries == 0 then
    return nil
  end

  local function is_file(i)
    return entries[i] and entries[i].type == "file"
  end

  local index = start_index or 0
  for _ = 1, #entries do
    index = index + direction
    if index < 1 then
      index = #entries
    elseif index > #entries then
      index = 1
    end
    if is_file(index) then
      return index
    end
  end

  return nil
end

local function get_state(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  return picker, picker and picker._treeview_state or nil
end

local function refresh_picker(picker, state, keep_node)
  local prompt = action_state.get_current_line()
  finder.update_state(state, prompt)
  state.pending_reselect_node = keep_node
  state.pending_prompt = prompt
  picker:refresh(finder.finder(state))
end

M.actions = {}

function M.actions.toggle_dir(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  local selection = action_state.get_selected_entry()
  if not selection or selection.type ~= "dir" then
    return
  end
  local node = selection.value
  finder.toggle_node(state, node)
  refresh_picker(picker, state, node)
end

function M.actions.expand_dir(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  local selection = action_state.get_selected_entry()
  if not selection or selection.type ~= "dir" then
    return
  end
  local node = selection.value
  finder.set_node_expanded(state, node, true)
  refresh_picker(picker, state, node)
end

function M.actions.collapse_dir(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  local selection = action_state.get_selected_entry()
  if not selection or selection.type ~= "dir" then
    return
  end
  local node = selection.value
  finder.set_node_expanded(state, node, false)
  refresh_picker(picker, state, node)
end

function M.actions.expand_all(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  finder.set_all_expanded(state, true)
  local selection = action_state.get_selected_entry()
  refresh_picker(picker, state, selection and selection.value or nil)
end

function M.actions.collapse_all(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  local selection = action_state.get_selected_entry()
  local keep_node = selection and selection.value or nil
  if selection and (selection.type == "file" or selection.type == "dir") then
    keep_node = finder.get_top_level_dir(state, selection.value) or selection.value
  end
  finder.set_all_expanded(state, false)
  refresh_picker(picker, state, keep_node)
end

function M.actions.next_file(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  local prompt = action_state.get_current_line()
  local entries = finder.update_state(state, prompt)
  local selection = action_state.get_selected_entry()
  local current_index = find_entry_index(entries, selection)
  local target_index = find_next_file_index(entries, current_index, 1)
  if not target_index then
    return
  end
  picker:set_selection(picker:get_row(target_index))
end

function M.actions.prev_file(prompt_bufnr)
  local picker, state = get_state(prompt_bufnr)
  if not picker or not state then
    return
  end
  local prompt = action_state.get_current_line()
  local entries = finder.update_state(state, prompt)
  local selection = action_state.get_selected_entry()
  local current_index = find_entry_index(entries, selection)
  local target_index = find_next_file_index(entries, current_index, -1)
  if not target_index then
    return
  end
  picker:set_selection(picker:get_row(target_index))
end

function M.treeview(opts)
  opts = opts or {}
  opts = vim.tbl_deep_extend("force", M.config, opts)

  local root = finder.build_tree(opts)
  local state = finder.new_state(root, opts)

  local picker
  picker = pickers.new(opts, {
    prompt_title = "Treeview",
    finder = finder.finder(state),
    sorter = sorters.empty(),
    sorting_strategy = "ascending",
    selection_strategy = "follow",
    on_input_filter_cb = function(prompt)
      local _, index = finder.update_state(state, prompt)
      if prompt ~= "" and index then
        picker.default_selection_index = index
        picker._selection_entry = nil
        picker._selection_row = nil
      else
        picker.default_selection_index = nil
      end
    end,
    previewer = finder.previewer(),
    attach_mappings = function(prompt_bufnr, map)
      local default_mappings = {
        i = {
          ["<C-Down>"] = M.actions.next_file,
          ["<C-Up>"] = M.actions.prev_file,
          ["<Right>"] = M.actions.expand_dir,
          ["<Left>"] = M.actions.collapse_dir,
          ["<C-Right>"] = M.actions.expand_all,
          ["<C-Left>"] = M.actions.collapse_all,
        },
        n = {
          ["<C-Down>"] = M.actions.next_file,
          ["<C-Up>"] = M.actions.prev_file,
          ["<Right>"] = M.actions.expand_dir,
          ["<Left>"] = M.actions.collapse_dir,
          ["<C-Right>"] = M.actions.expand_all,
          ["<C-Left>"] = M.actions.collapse_all,
        },
      }

      local configured = opts.mappings or {}
      for mode, mappings in pairs(default_mappings) do
        local mode_overrides = configured[mode] or {}
        for key, action in pairs(mappings) do
          local override = mode_overrides[key]
          local handler = override
          if handler == nil then
            handler = action
          end
          if handler ~= false then
            map(mode, key, function()
              handler(prompt_bufnr)
            end)
          end
        end
      end

      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if not selection or selection.type == "dir" then
          return
        end
        actions.file_edit(prompt_bufnr)
      end)
      return true
    end,
  })
  picker._treeview_state = state
  picker:register_completion_callback(function(p)
    if not state.pending_reselect_node then
      return
    end
    local prompt = state.pending_prompt or p:_get_prompt()
    local entries = finder.update_state(state, prompt)
    local index = find_entry_index(entries, { value = state.pending_reselect_node })
    state.pending_reselect_node = nil
    state.pending_prompt = nil
    if index then
      p:set_selection(p:get_row(index))
      local win = p.results_win
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          vim.cmd("normal! zz")
        end)
      end
    end
  end)
  picker:find()
end

return M
