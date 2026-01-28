Extension Plan: Telescope Tree View

Goal
- Provide a Telescope extension named treeview that displays files in a tree layout.
- Preserve find_files behavior for discovery and previewing.
- Reorder directories by match strength using max descendant match.

User Decisions
- Source: fd/rg like find_files.
- Tree glyphs: Unicode.
- Previewer: same as find_files for files; empty for directories.
- Directory score: max descendant match.

Implementation Plan

1) Extension layout
- lua/treeview/init.lua: main picker logic
- lua/treeview/finder.lua: file list -> tree -> flattened entries
- lua/treeview/scoring.lua: fuzzy scoring + max-descendant directory scoring
- lua/telescope/_extensions/treeview.lua: register extension export

2) File list collection (find_files-like)
- Use a oneshot job to collect file list:
  - Prefer fd, fallback to rg --files
  - Mirror find_files options: hidden, no_ignore, no_ignore_parent, follow, search_dirs
- Normalize paths:
  - abs_path for preview/open
  - rel_path for display/scoring

3) Tree model
- Build a root node with nested children:
  - Node: { name, path, type, children, depth, score }
- Preserve insertion order while building

4) Scoring
- Fuzzy-score each file rel_path against current query
- Directory score = max descendant file score

5) Reordering
- For each directory:
  - Sort children by score desc, name asc
- Keep hierarchy intact while bubbling best matches

6) Flatten for display
- Unicode tree glyphs: ├─, └─, │
- Example:
  - src
  - ├─ lib
  - │  ├─ foo.lua
  - └─ init.lua

7) Entry maker
- display: tree line + name
- ordinal: rel_path (matching)
- path: abs_path (previewer + open)

8) Previewer
- Use conf.file_previewer for files
- Directories: empty preview

9) Actions
- <CR> on file: default open
- <CR> on dir: no-op for now (tree-only)
- Optional later: collapse/expand + refresh

10) Performance
- Cache tree + flattened list
- Rebuild/reorder only on input change
- Refresh picker with new flattened list on query update
