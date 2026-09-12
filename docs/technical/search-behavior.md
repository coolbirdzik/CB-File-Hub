# Shared search behavior

Use `SearchTextField` for search inputs, including dialogs and local list
filters. It supplies a transparent Material ancestor for the Fluent shell,
a single line and the search keyboard action. Native text selection and
editing shortcuts must remain intact.

When listening to a controller, use `SearchTextController.addQueryListener`,
not `TextEditingController.addListener`. Query listeners ignore selection-only
changes and wait for IME composition to commit. Ordinary controller listeners
remain available to Flutter for painting the caret and selection.

Use `SearchQuery.tags` for `#tag` parsing on desktop and mobile. Spaces inside
a tag are preserved; another `#` introduces another tag. Use
`TextUtils.matchesSearch` for every text filter. It folds case, Unicode accents
and combining marks, so `chao` finds `chào` (and the same rule applies to tags,
filenames, paths, and picker suggestions). Search scope and available options
still depend on the data source: Network filters its current listing;
folder search supports recursive traversal; Video Library searches its sources.

Asynchronous searches use `SearchRequestGuard`. Begin a revision for new work,
invalidate on clear/navigation/refresh, and dispose it with the owner. Check
the revision before applying results or errors. Debounced searches invalidate
on edit, before the debounce timer fires.

After deletion, use `SearchQuery.isRemovedPath` for both exact files and directory
descendants. Rendering, keyboard navigation and select-all must use the same
filtered collection. Video Library invalidates and reloads its separate live
search source while retaining the current query; active tag searches also
respond to tag changes.

Regression coverage: `search_text_field_test.dart`, `search_tag_update_test.dart`,
`network_list_view_test.dart`, and `video_library_search_test.dart`.
