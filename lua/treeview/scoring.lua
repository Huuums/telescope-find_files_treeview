local fzy = require("telescope.algos.fzy")

local M = {}

local function score_path(query, path)
  if query == "" then
    return 0
  end

  if not fzy.has_match(query, path) then
    return nil
  end

  return fzy.score(query, path)
end

local function score_node(node, query)
  if node.type == "file" then
    node.score = score_path(query, node.rel_path)
    return node.score
  end

  local best = nil
  for _, child in ipairs(node.children) do
    local child_score = score_node(child, query)
    if child_score ~= nil and (best == nil or child_score > best) then
      best = child_score
    end
  end

  if query == "" then
    node.score = 0
  else
    node.score = best
  end

  return node.score
end

function M.score_tree(root, query)
  score_node(root, query or "")
end

return M
