# Hidden Settings tab emitted orphan semantics nodes

The second supplied log reported AXTree node 355 repeatedly, followed by nodes
76/1366 and a Dart `SemanticsNode._replaceChildren` assertion (`!child.attached`)
after hot reload. This is a separate finding from the native drag crash.

## Live identification

Read-only Dart VM service inspection of the running app identified node 355 as
an overlay child with `traversalChildIdentifier: _OverlayPortalState#abefb`.
Its portal's widget ancestors led to a Material Slider (value 20, range 0–100)
in SettingsScreen, inside the retained tab IndexedStack. The current tab was a
file browser. Node 76 belonged to that browser's content semantics subtree.

Flutter 3.47.2 Material Slider creates its value-indicator OverlayPortal with
`..show()` even when it paints no label. All tab content previously shared the
app overlay. IndexedStack excludes inactive tab content from semantics, but
the portal child in the app overlay survives outside that exclusion. Its
traversal anchor is consequently absent from the serialized tree.

## Change

TabScreen now wraps each cached tab in a keyed TabContentOverlay. Its stable
OverlayEntry owns the tab content, so nearest-overlay portals stay within the
same IndexedStack visibility boundary as their anchors. Tab state remains
mounted across switches, child updates reach the entry, and closing the tab
disposes the entry. Root Navigator dialogs continue using the root Navigator.

## Evidence and limits

- A minimal IndexedStack with an inactive slider tab emitted two unreachable
  semantics nodes before the fix (`orphan node 5`, `orphan node 6`).
- The same scenario with TabContentOverlay passes. The regression test checks
  the incremental serialized traversal graph, including missing child refs,
  rather than relying only on the render-tree snapshot.
- Five switch/reassembly cycles preserve slider State instances. Updating tab
  content and removing the hidden tab also pass.
- Tag input additions/removals, tooltip hover, dialog reassembly and teardown
  pass. Ten related widget tests pass in total.
- The original `!child.attached` assertion itself was not reproduced in the
  isolated tag test; this fix targets the confirmed upstream orphan trigger.
- A fresh Windows app session remains necessary to verify the native bridge
  over normal use. Hot reload of an already-invalid accessibility tree does not
  constitute a fresh verification; the app also caches its tab widget wrappers.

Run from cb_file_manager:

```powershell
flutter test test/ui/widgets/tag_semantics_stability_test.dart test/design_system/cb_tooltip_semantics_test.dart test/design_system/primitives/cb_fluent_tooltip_test.dart test/ui/widgets/resizable_dialog_test.dart --reporter expanded
```

For manual verification, restart the app, open Settings with sliders, switch to
a file tab, edit tags, switch back and forth, then close Settings. Check for
AXTree errors while keeping accessibility enabled. Do not disable semantics or
suppress Flutter errors as a workaround.
