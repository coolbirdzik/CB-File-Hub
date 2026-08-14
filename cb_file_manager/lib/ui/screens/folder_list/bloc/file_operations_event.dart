import 'package:equatable/equatable.dart';
import 'dart:io';

abstract class FileOperationsEvent extends Equatable {
  const FileOperationsEvent();

  @override
  List<Object?> get props => [];
}

// ─── Copy / Cut ────────────────────────────────────────────────────

class FileOperationsCopy extends FileOperationsEvent {
  final List<FileSystemEntity> entities;
  const FileOperationsCopy(this.entities);

  @override
  List<Object> get props => [entities];
}

class FileOperationsCut extends FileOperationsEvent {
  final List<FileSystemEntity> entities;
  const FileOperationsCut(this.entities);

  @override
  List<Object> get props => [entities];
}

// ─── Paste ─────────────────────────────────────────────────────────

class FileOperationsPaste extends FileOperationsEvent {
  final String destinationPath;
  const FileOperationsPaste(this.destinationPath);

  @override
  List<Object> get props => [destinationPath];
}

// ─── Delete ────────────────────────────────────────────────────────

class FileOperationsDeleteFiles extends FileOperationsEvent {
  final List<String> filePaths;
  final bool permanent;
  const FileOperationsDeleteFiles(this.filePaths, {this.permanent = false});

  @override
  List<Object> get props => [filePaths, permanent];
}

class FileOperationsDeleteItems extends FileOperationsEvent {
  final List<String> filePaths;
  final List<String> folderPaths;
  final bool permanent;
  const FileOperationsDeleteItems({
    this.filePaths = const [],
    this.folderPaths = const [],
    this.permanent = false,
  });

  @override
  List<Object> get props => [filePaths, folderPaths, permanent];
}

class FileOperationsRetryDeleteAsAdministrator extends FileOperationsEvent {
  final List<String> failedPaths;

  const FileOperationsRetryDeleteAsAdministrator(this.failedPaths);

  @override
  List<Object> get props => [failedPaths];
}

// ─── Rename ────────────────────────────────────────────────────────

class FileOperationsRename extends FileOperationsEvent {
  final FileSystemEntity entity;
  final String newName;
  const FileOperationsRename(this.entity, this.newName);

  @override
  List<Object> get props => [entity, newName];
}

// ─── Clipboard ─────────────────────────────────────────────────────

class FileOperationsClearClipboard extends FileOperationsEvent {
  const FileOperationsClearClipboard();
}
