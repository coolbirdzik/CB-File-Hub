import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import '../../utils/format_utils.dart';
import '../mixins/selection_mixin.dart';

class TrashBinScreen extends StatefulWidget {
  const TrashBinScreen({Key? key}) : super(key: key);

  @override
  State<TrashBinScreen> createState() => _TrashBinScreenState();
}

class _TrashBinScreenState extends State<TrashBinScreen> with SelectionMixin {
  final TrashManager _trashManager = TrashManager();
  List<TrashItem> _trashItems = [];
  bool _isLoading = true;
  String? _errorCode;
  List<String> _errorArgs = [];
  bool _showSystemOptions = false;

  @override
  void initState() {
    super.initState();
    _loadTrashItems();
  }

  Future<void> _loadTrashItems() async {
    setState(() {
      _isLoading = true;
      _errorCode = null;
      _errorArgs = [];
    });

    try {
      final items = await _trashManager.getTrashItems();
      setState(() {
        _trashItems = items;
        _isLoading = false;

        // Determine if we have system items to show system-specific options
        _showSystemOptions =
            Platform.isWindows && items.any((item) => item.isSystemTrashItem);
      });
    } catch (e) {
      setState(() {
        _errorCode = 'load';
        _errorArgs = [e.toString()];
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreItem(TrashItem item) async {
    setState(() {
      _isLoading = true;
    });

    try {
      bool success = false;

      if (item.isSystemTrashItem && Platform.isWindows) {
        // Restore from Windows Recycle Bin
        success = await _trashManager
            .restoreFromWindowsRecycleBin(item.trashFileName);
      } else {
        // Restore from internal trash
        success = await _trashManager.restoreFromTrash(item.trashFileName);
      }

      if (success) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(l10n.itemRestoredSuccess(item.displayNameValue))),
          );
        }
        // Refresh the trash items
        await _loadTrashItems();
      } else {
        setState(() {
          _isLoading = false;
          _errorCode = 'restore_failed';
          _errorArgs = [item.displayNameValue];
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorCode = 'restore_error';
        _errorArgs = [e.toString()];
      });
    }
  }

  Future<void> _deleteItem(TrashItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.permanentDeleteTitle),
            content: Text(l10n.confirmDeletePermanent(item.displayNameValue)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.delete,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() {
        _isLoading = true;
      });

      try {
        bool success = false;

        if (item.isSystemTrashItem && Platform.isWindows) {
          // Delete from Windows Recycle Bin
          success = await _trashManager
              .deleteFromWindowsRecycleBin(item.trashFileName);
        } else {
          // Delete from internal trash
          success = await _trashManager.deleteFromTrash(item.trashFileName);
        }

        if (success) {
          if (mounted) {
            final l10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(l10n.itemPermanentlyDeleted(item.displayNameValue))),
            );
          }
          // Refresh the trash items
          await _loadTrashItems();
        } else {
          setState(() {
            _isLoading = false;
            _errorCode = 'delete_failed';
            _errorArgs = [item.displayNameValue];
          });
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorCode = 'delete_error';
          _errorArgs = [e.toString()];
        });
      }
    }
  }

  Future<void> _emptyTrash() async {
    final l10n = AppLocalizations.of(context)!;
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.emptyTrash),
            content: Text(l10n.emptyTrashConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.emptyTrashButton,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() {
        _isLoading = true;
      });

      try {
        final success = await _trashManager.emptyTrash();

        if (success) {
          if (mounted) {
            final l10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.trashEmptiedSuccess)),
            );
          }
          // Refresh the trash items
          await _loadTrashItems();
        } else {
          setState(() {
            _isLoading = false;
            _errorCode = 'empty_failed';
            _errorArgs = [];
          });
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorCode = 'empty_error';
          _errorArgs = [e.toString()];
        });
      }
    }
  }

  Future<void> _openSystemRecycleBin() async {
    if (Platform.isWindows) {
      try {
        await _trashManager.openWindowsRecycleBin();
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(l10n.errorOpeningRecycleBinWithError(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _restoreSelectedItems() async {
    setState(() {
      _isLoading = true;
    });

    try {
      int successCount = 0;
      int failedCount = 0;

      for (final trashFileName in selectedPaths) {
        final item = _trashItems.firstWhere(
          (item) => item.trashFileName == trashFileName,
          orElse: () => throw Exception('Item not found'),
        );

        bool success = false;
        if (item.isSystemTrashItem && Platform.isWindows) {
          success = await _trashManager
              .restoreFromWindowsRecycleBin(item.trashFileName);
        } else {
          success = await _trashManager.restoreFromTrash(item.trashFileName);
        }

        if (success) {
          successCount++;
        } else {
          failedCount++;
        }
      }

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final String message = failedCount > 0
            ? l10n.itemsRestoredWithFailures(successCount, failedCount)
            : l10n.itemsRestoredSuccess(successCount);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );

        // Clear selection and refresh
        exitSelectionMode();
      }

      await _loadTrashItems();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorCode = 'restore_items_error';
        _errorArgs = [e.toString()];
      });
    }
  }

  Future<void> _deleteSelectedItems() async {
    final l10n = AppLocalizations.of(context)!;
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.permanentlyDeleteItemsTitle(selectedPaths.length)),
            content: Text(l10n.confirmPermanentlyDeleteThese),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.delete,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() {
        _isLoading = true;
      });

      try {
        int successCount = 0;
        int failedCount = 0;

        for (final trashFileName in selectedPaths) {
          final item = _trashItems.firstWhere(
            (item) => item.trashFileName == trashFileName,
            orElse: () => throw Exception('Item not found'),
          );

          bool success = false;
          if (item.isSystemTrashItem && Platform.isWindows) {
            success = await _trashManager
                .deleteFromWindowsRecycleBin(item.trashFileName);
          } else {
            success = await _trashManager.deleteFromTrash(item.trashFileName);
          }

          if (success) {
            successCount++;
          } else {
            failedCount++;
          }
        }

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          final String message = failedCount > 0
              ? l10n.itemsDeletedWithFailures(successCount, failedCount)
              : l10n.itemsPermanentlyDeletedCount(successCount);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );

          // Clear selection and refresh
          exitSelectionMode();
        }

        await _loadTrashItems();
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorCode = 'delete_items_error';
          _errorArgs = [e.toString()];
        });
      }
    }
  }

  void _toggleSelectionMode() {
    toggleSelectionMode();
  }

  void _toggleItemSelection(String trashFileName) {
    setState(() {
      if (selectedPaths.contains(trashFileName)) {
        selectedPaths.remove(trashFileName);
      } else {
        selectedPaths.add(trashFileName);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (selectedPaths.length == _trashItems.length) {
        // If all are selected, deselect all
        selectedPaths.clear();
      } else {
        // Otherwise, select all
        selectedPaths.clear();
        for (final item in _trashItems) {
          selectedPaths.add(item.trashFileName);
        }
      }
    });
  }

  // Helper methods using FormatUtils
  String _formatDate(DateTime date) => FormatUtils.formatDateWithTime(date);
  String _formatFileSize(int bytes) => FormatUtils.formatFileSize(bytes);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trashBin),
        actions: [
          if (isSelectionMode) ...[
            IconButton(
              icon: Icon(PhosphorIconsLight.checkSquare),
              tooltip: l10n.selectAll,
              onPressed: _selectAll,
            ),
            IconButton(
              icon: Icon(PhosphorIconsLight.arrowsClockwise),
              tooltip: l10n.restoreSelected,
              onPressed: selectedPaths.isEmpty ? null : _restoreSelectedItems,
            ),
            IconButton(
              icon: Icon(PhosphorIconsLight.trash),
              tooltip: l10n.deleteSelected,
              onPressed: selectedPaths.isEmpty ? null : _deleteSelectedItems,
            ),
          ] else ...[
            IconButton(
              icon: Icon(PhosphorIconsLight.checkSquare),
              tooltip: l10n.selectItems,
              onPressed: _trashItems.isEmpty ? null : _toggleSelectionMode,
            ),
            if (Platform.isWindows && _showSystemOptions)
              IconButton(
                icon: Icon(PhosphorIconsLight.arrowSquareOut),
                tooltip: l10n.openRecycleBin,
                onPressed: _openSystemRecycleBin,
              ),
            IconButton(
              icon: Icon(PhosphorIconsLight.trash),
              tooltip: l10n.emptyTrashTooltip,
              onPressed: _trashItems.isEmpty ? null : _emptyTrash,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  String _getErrorMessage(AppLocalizations l10n) {
    if (_errorCode == null) return '';
    final a = _errorArgs;
    switch (_errorCode!) {
      case 'load':
        return l10n.errorLoadingTrashItemsWithError(a.isEmpty ? '' : a[0]);
      case 'restore_failed':
        return l10n.failedToRestore(a.isEmpty ? '' : a[0]);
      case 'restore_error':
        return l10n.errorRestoringItemWithError(a.isEmpty ? '' : a[0]);
      case 'delete_failed':
        return l10n.failedToDelete(a.isEmpty ? '' : a[0]);
      case 'delete_error':
        return l10n.errorDeletingItemWithError(a.isEmpty ? '' : a[0]);
      case 'empty_failed':
        return l10n.failedToEmptyTrash;
      case 'empty_error':
        return l10n.errorEmptyingTrashWithError(a.isEmpty ? '' : a[0]);
      case 'restore_items_error':
        return l10n.errorRestoringItemsWithError(a.isEmpty ? '' : a[0]);
      case 'delete_items_error':
        return l10n.errorDeletingItemsWithError(a.isEmpty ? '' : a[0]);
      default:
        return a.join(' ');
    }
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorCode != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIconsLight.warning,
                color: Theme.of(context).colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _getErrorMessage(l10n),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTrashItems,
                icon: Icon(PhosphorIconsLight.arrowsClockwise),
                label: Text(l10n.tryAgain),
              ),
            ],
          ),
        ),
      );
    }

    if (_trashItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsLight.trash,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.trashIsEmpty,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.itemsDeletedWillAppearHere,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTrashItems,
              icon: Icon(PhosphorIconsLight.arrowsClockwise),
              label: Text(l10n.refresh),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTrashItems,
      child: ListView.builder(
        itemCount: _trashItems.length,
        itemBuilder: (context, index) {
          final item = _trashItems[index];
          final isSelected = selectedPaths.contains(item.trashFileName);

          return ListTile(
            leading: _getFileIcon(context, item.displayNameValue),
            title: Text(
              item.displayNameValue,
              style: item.isSystemTrashItem
                  ? TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
            subtitle: Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context)!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.originalLocation(item.originalPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Text(
                          l10n.deletedAt(_formatDate(item.trashedDate),
                              _formatFileSize(item.size)),
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (item.isSystemTrashItem) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Text(
                              l10n.systemLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
            isThreeLine: true,
            selected: isSelected,
            trailing: isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (value) =>
                        _toggleItemSelection(item.trashFileName),
                  )
                : Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context)!;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(PhosphorIconsLight.arrowsClockwise,
                                size: 20),
                            tooltip: l10n.restoreTooltip,
                            onPressed: () => _restoreItem(item),
                          ),
                          IconButton(
                            icon: Icon(PhosphorIconsLight.trash, size: 20),
                            tooltip: l10n.deletePermanentlyTooltip,
                            onPressed: () => _deleteItem(item),
                          ),
                        ],
                      );
                    },
                  ),
            onTap: isSelectionMode
                ? () => _toggleItemSelection(item.trashFileName)
                : null,
            onLongPress: () {
              if (!isSelectionMode) {
                _toggleSelectionMode();
                _toggleItemSelection(item.trashFileName);
              }
            },
          );
        },
      ),
    );
  }

  Widget _getFileIcon(BuildContext context, String fileName) {
    final colorScheme = Theme.of(context).colorScheme;

    // Use FileTypeUtils to determine file type
    if (FileTypeUtils.isImageFile(fileName)) {
      return CircleAvatar(
        backgroundColor: colorScheme.primary,
        child: Icon(PhosphorIconsLight.image, color: colorScheme.onPrimary),
      );
    }

    // Video file
    if (FileTypeUtils.isVideoFile(fileName)) {
      return CircleAvatar(
        backgroundColor: colorScheme.error,
        child:
            Icon(PhosphorIconsLight.videoCamera, color: colorScheme.onPrimary),
      );
    }

    // Audio file
    if (FileTypeUtils.isAudioFile(fileName)) {
      return CircleAvatar(
        backgroundColor: colorScheme.tertiary,
        child:
            Icon(PhosphorIconsLight.musicNotes, color: colorScheme.onPrimary),
      );
    }

    // Document file
    if (FileTypeUtils.isDocumentFile(fileName) ||
        FileTypeUtils.isSpreadsheetFile(fileName) ||
        FileTypeUtils.isPresentationFile(fileName)) {
      return CircleAvatar(
        backgroundColor: colorScheme.secondary,
        child: Icon(PhosphorIconsLight.fileText, color: colorScheme.onPrimary),
      );
    }

    // Default icon
    return CircleAvatar(
      backgroundColor: colorScheme.onSurfaceVariant,
      child: Icon(PhosphorIconsLight.file, color: colorScheme.onPrimary),
    );
  }
}
