# Tree View UI Pattern

**Purpose**: Reusable, virtualised tree component (`GenericTreeView<T>`) and how it is wired into the tag manager, the local file browser, and the network browser.

## Component

**Location**: `lib/ui/widgets/tree_view/`

| File | Responsibility |
|------|----------------|
| `tree_node.dart` | `TreeNode<T>` data model |
| `generic_tree_view.dart` | `GenericTreeView<T>` widget + flatten/virtualisation |
| `tree_row.dart` | Internal row shell (indent + chevron) and placeholder rows |
| `tree_view.dart` | Barrel export (`import '.../tree_view/tree_view.dart'`) |

### Design

The tree flattens its **visible** rows into a single `ListView.builder` with a fixed `itemExtent`. This keeps scrolling cheap even with tens of thousands of nodes — only on-screen rows are built. It follows the same flat-list virtualisation approach used by the disk cleaner screen.

Expansion state lives on each `TreeNode` (`isExpanded`). The widget owns the chevron tap, lazy-load lifecycle, and `setState` for built-in interactions.

### `TreeNode<T>`

```dart
TreeNode<T>(
  id: 'stable-unique-id',   // identity, selection, expansion
  data: payload,            // read by the row builder
  isLeaf: false,            // leaves never show a chevron or load children
  children: null,           // null = not loaded yet (lazy); [] = loaded empty
  isExpanded: false,
);
```

- `children == null` + not a leaf → fetched via `childrenLoader` on first expand, then cached on the node.
- `children == []` → loaded but empty (no chevron action).

### `GenericTreeView<T>` key parameters

| Param | Purpose |
|-------|---------|
| `roots` | Top-level nodes, order preserved |
| `itemBuilder` | Builds the row body (icon/name/badges); the shell adds indent + chevron |
| `childrenLoader` | `Future<List<TreeNode<T>>> Function(node)` for lazy children |
| `itemExtent` | Fixed row height — required for virtualisation |
| `nodeFilter` | Hide nodes whose `id` is not in a precomputed visible set |
| `selectedIds` / `focusedId` | Highlight selected / focused rows |
| `maxChildrenPerNode` | Soft cap (default 2000); excess collapses into a `… and N more` row |
| `onTap` / `onDoubleTap` / `onSecondary` | Row interactions |

### Lazy loading states

The tree renders inline placeholder rows automatically:
- **Loading** — spinner row while `childrenLoader` is in flight.
- **Error** — "Failed to load. Tap to retry." (re-runs the loader).
- **Truncated** — "… and N more, click to load" when children exceed `maxChildrenPerNode`.

## Integrations

### Tag manager (`tag_management_screen.dart`)

- View mode is `_TagViewMode { list, grid, tree }`, chosen via the `PhosphorIconsLight.eye` `PopupMenuButton` (same UX as the file/network browsers' view-mode menu).
- Roots = root parent tags (`TagHierarchyManager.getRootParents()`) + standalone tags. Children come synchronously from `getChildren()`.
- Eager tree (no lazy loader) — the hierarchy is already fully in memory.

Two gotchas handled here:

1. **Cache the roots.** `TreeNode`s carry expansion state, so rebuilding them on every `setState` collapses the tree and resets scroll. Roots are cached in `_cachedTreeRoots` and only rebuilt when a signature (tag count + full hierarchy tree) changes. The `nodeFilter`/visible-set is still recomputed each build (cheap, follows search/filter).
2. **Case mismatch.** `TagHierarchyManager` stores names **normalized** (lowercased + trimmed), but `_allTags` / `_filteredTags` keep display case. Nodes built from the hierarchy must be mapped back to display case via `_normalizedToDisplay`, otherwise `nodeFilter` hides every parent/child (their normalized ids never match the display-cased visible set).

Search/filter keeps ancestors of matches visible: a DFS marks a node visible if it or any descendant matches, then adds the node plus its ancestor path to the `showIds` set used by `nodeFilter`.

### Local file browser

- `ViewMode.tree` added to `lib/ui/screens/folder_list/folder_list_state.dart`.
- `FileListViewBuilder.build` delegates tree mode to `FileTreeView` (`lib/ui/widgets/file_tree_view.dart`).
- Roots = current directory's folders + files. Children are loaded lazily via `Directory.listSync` inside a `compute` isolate (folders first, then files, alphabetical), cached on the node.
- Roots are rebuilt only when the directory listing signature changes (path + counts + last entry), preserving expansion state across unrelated `setState`s.
- Discoverability: `ViewMode.tree` is in the cycle (`preferences_manager_mixin.dart`), the mobile bottom-sheet picker, and the `shared_action_bar.dart` popup menu.

### Network browser

- `BrowserLikeCollectionView<T>` gained optional `treeItemBuilder`, `treeChildrenLoader`, and `treeIsLeaf`. When `viewMode == ViewMode.tree` and a `treeItemBuilder` is supplied, it renders an internal `_BrowserTreeView` that adapts the flat `items` list into `TreeNode<T>` roots.
- `network_browser_screen.dart` supplies `_loadNetworkChildren` (reuses `currentService.listDirectory`) and `_buildNetworkTreeRow`. Double-tap navigates folders / opens files.

## When to use

Reach for `GenericTreeView<T>` for any hierarchical, expandable list where the dataset can be large and children may be loaded on demand. Provide a `childrenLoader` for lazy data (filesystem, network) or pre-populate `children` for fully in-memory hierarchies (tags).

## Reference implementations

- Tags (eager, cached, case-mapped): `lib/ui/screens/tag_management/tag_management_screen.dart` → `_buildTagsTreeView`
- Local files (lazy, isolate scan): `lib/ui/widgets/file_tree_view.dart`
- Network (lazy via service): `lib/ui/screens/network_browsing/network_browser_screen.dart` → `_loadNetworkChildren`
