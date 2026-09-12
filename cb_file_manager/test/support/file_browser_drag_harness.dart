import 'dart:io';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import 'package:cb_file_manager/ui/widgets/file_list_view_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Listing state is supplied by the fixture; selection and all layout/gesture
// widgets are the same ones used by the browser.
class _ListingStub implements FolderListBloc {
  _ListingStub(this.state);
  @override
  final FolderListState state;
  @override
  Stream<FolderListState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FileBrowserDragHarness extends StatefulWidget {
  const FileBrowserDragHarness({
    super.key,
    required this.files,
    required this.destination,
    required this.mode,
    required this.onMove,
    required this.onExternalDrag,
  });
  final List<File> files;
  final Directory destination;
  final ViewMode mode;
  final Future<void> Function(List<String>, String) onMove;
  final ValueChanged<List<String>> onExternalDrag;
  @override
  State<FileBrowserDragHarness> createState() => FileBrowserDragHarnessState();
}

class FileBrowserDragHarnessState extends State<FileBrowserDragHarness> {
  final selection = SelectionBloc();
  final previewWidth = ValueNotifier<double>(300);
  late final FolderListState listing;
  late final FolderListBloc folderBloc;
  late final TabbedFolderDragSelectionController dragSelection;
  @override
  void initState() {
    super.initState();
    listing = FolderListState(
      widget.destination.parent.path,
      folders: [widget.destination],
      files: widget.files,
      viewMode: widget.mode,
    );
    folderBloc = _ListingStub(listing);
    dragSelection = TabbedFolderDragSelectionController(
      folderListBloc: folderBloc,
      selectionBloc: selection,
    );
  }

  @override
  void dispose() {
    dragSelection.dispose();
    previewWidth.dispose();
    selection.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: const [AppLocalizationsDelegate()],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<SelectionBloc>.value(value: selection),
          BlocProvider<FolderListBloc>.value(value: folderBloc),
        ],
        child: BlocBuilder<SelectionBloc, SelectionState>(
          builder: (context, state) {
            return FileListViewBuilder.build(
              state: listing,
              selectionState: state,
              isDesktopPlatform: true,
              onNavigateToPath: (_) {},
              onFileTap: (_, _) {},
              toggleFileSelection:
                  (path, {shiftSelect = false, ctrlSelect = false}) =>
                      selection.add(
                        ToggleFileSelection(
                          path,
                          shiftSelect: shiftSelect,
                          ctrlSelect: ctrlSelect,
                        ),
                      ),
              toggleFolderSelection:
                  (path, {shiftSelect = false, ctrlSelect = false}) =>
                      selection.add(
                        ToggleFolderSelection(
                          path,
                          shiftSelect: shiftSelect,
                          ctrlSelect: ctrlSelect,
                        ),
                      ),
              clearSelection: () => selection.add(ClearSelection()),
              dragSelectionController: dragSelection,
              showFileTags: false,
              showDeleteTagDialog: (_, _, _) {},
              showAddTagToFileDialog: (_, _) {},
              toggleSelectionMode: () {},
              columnVisibility: const ColumnVisibility(),
              showContextMenu: (_, _) {},
              isPreviewPaneVisible: false,
              previewPaneWidthListenable: previewWidth,
              onZoomLevelChanged: (_) {},
              onPreviewPaneWidthChanged: (_) {},
              onPreviewPaneWidthCommitted: (_) {},
              onPreviewPaneToggled: () {},
              onStartFileDrag: widget.onExternalDrag,
              onMoveItemsToFolder: widget.onMove,
            );
          },
        ),
      ),
    ),
  );
}
