# find_files_treeview

Tree view file picker for Telescope. It keeps the familiar file previewer, while rendering results as a directory tree. When you type a query, directories are reordered by the best matching file in their subtree, and matching directories temporarily expand.

## Requirements
- Neovim 0.9+ (uses `vim.uv` and `vim.json`)
- `nvim-telescope/telescope.nvim`
- Optional: `nvim-tree/nvim-web-devicons` for icons
- `fd` or `rg` on your PATH

## Install (lazy.nvim)
```lua
{
  "nvim-telescope/telescope.nvim",
  dependencies = {
    { "nvim-lua/plenary.nvim" },
    { "nvim-tree/nvim-web-devicons", optional = true },
    { dir = "/path/to/find_files_treeview" },
  },
  opts = function(_, opts)
    opts.extensions = opts.extensions or {}
    opts.extensions["find_files_treeview"] = {
      icons = true,
    }
  end,
  config = function(_, opts)
    require("telescope").setup(opts)
    require("telescope").load_extension("find_files_treeview")
  end,
}
```

## Usage
```vim
:Telescope find_files_treeview treeview
```

Compatibility alias (if loaded):
```vim
:Telescope treeview
```

## Options
All options can be passed to the picker or set in `telescope.setup` under `extensions["find_files_treeview"]`.

- `icons` (boolean, default: auto)
  - Show file and folder icons when `nvim-web-devicons` is available.
- `persist` (boolean, default: true)
  - Persist expanded/collapsed directories across sessions.
- `persist_path` (string)
  - Custom persistence file path. Default: `stdpath("state")/treeview.json`.
- `mappings` (table)
  - Override default keybindings.

## Default mappings
- `<Right>`: expand directory
- `<Left>`: collapse directory
- `<C-Right>`: expand all
- `<C-Left>`: collapse all
- `<C-Down>`: next matching file
- `<C-Up>`: previous matching file

## Custom mappings
```lua
local actions = require("telescope").extensions.find_files_treeview.actions

require("telescope").setup({
  extensions = {
    ["find_files_treeview"] = {
      mappings = {
        i = {
          ["<C-j>"] = actions.next_file,
          ["<C-k>"] = actions.prev_file,
          ["<Right>"] = actions.expand_dir,
          ["<Left>"] = actions.collapse_dir,
        },
        n = {
          ["l"] = actions.expand_dir,
          ["h"] = actions.collapse_dir,
        },
      },
    },
  },
})
```

## Actions API
```lua
local actions = require("telescope").extensions.find_files_treeview.actions

actions.toggle_dir(prompt_bufnr)
actions.expand_dir(prompt_bufnr)
actions.collapse_dir(prompt_bufnr)
actions.expand_all(prompt_bufnr)
actions.collapse_all(prompt_bufnr)
actions.next_file(prompt_bufnr)
actions.prev_file(prompt_bufnr)
```
