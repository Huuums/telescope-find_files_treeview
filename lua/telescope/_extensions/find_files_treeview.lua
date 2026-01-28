return require("telescope").register_extension {
  setup = function(ext_config, _)
    require("treeview").setup(ext_config)
  end,
  exports = {
    treeview = require("treeview").treeview,
    actions = require("treeview").actions,
  },
}
