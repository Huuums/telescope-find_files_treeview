pcall(function()
  local telescope = require("telescope")
  telescope.load_extension("find_files_treeview")

  local ok_builtin, builtin = pcall(require, "telescope.builtin")
  if ok_builtin and builtin then
    builtin.find_files_treeview = function(opts)
      return telescope.extensions.find_files_treeview.treeview(opts)
    end
  end
end)
