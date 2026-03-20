import 'dart:io';
import 'package:equatable/equatable.dart';

/// Base class for all network browsing events
abstract class NetworkBrowsingEvent extends Equatable {
  const NetworkBrowsingEvent();

  @override
  List<Object?> get props => [];
}

/// Event to request list of available network services
class NetworkServicesListRequested extends NetworkBrowsingEvent {
  const NetworkServicesListRequested();
}

/// Event to request connection to a network location
class NetworkConnectionRequested extends NetworkBrowsingEvent {
  final String serviceName;
  final String host;
  final String username;
  final String? password;
  final int? port;
  final Map<String, dynamic>? additionalOptions;

  const NetworkConnectionRequested({
    required this.serviceName,
    required this.host,
    required this.username,
    this.password,
    this.port,
    this.additionalOptions,
  });

  @override
  List<Object?> get props => [
        serviceName,
        host,
        username,
        password,
        port,
        additionalOptions,
      ];
}

/// Event to request the contents of a network directory
class NetworkDirectoryRequested extends NetworkBrowsingEvent {
  final String path;

  const NetworkDirectoryRequested(this.path);

  @override
  List<Object?> get props => [path];
}

/// Event to request disconnection from a network location
class NetworkDisconnectRequested extends NetworkBrowsingEvent {
  final String path;

  const NetworkDisconnectRequested(this.path);

  @override
  List<Object?> get props => [path];
}

/// Event to request a file transfer (upload or download)
class NetworkFileTransferRequested extends NetworkBrowsingEvent {
  final String remotePath;
  final String localPath;
  final bool isDownload; // true for download, false for upload

  const NetworkFileTransferRequested({
    required this.remotePath,
    required this.localPath,
    required this.isDownload,
  });

  @override
  List<Object?> get props => [remotePath, localPath, isDownload];
}

/// Event to request deletion of a file
class NetworkFileDeleteRequested extends NetworkBrowsingEvent {
  final String path;

  const NetworkFileDeleteRequested(this.path);

  @override
  List<Object?> get props => [path];
}

/// Event to request creation of a directory
class NetworkDirectoryCreateRequested extends NetworkBrowsingEvent {
  final String path;

  const NetworkDirectoryCreateRequested(this.path);

  @override
  List<Object?> get props => [path];
}

/// Event to request deletion of a directory
class NetworkDirectoryDeleteRequested extends NetworkBrowsingEvent {
  final String path;

  const NetworkDirectoryDeleteRequested(this.path);

  @override
  List<Object?> get props => [path];
}

/// Event to request renaming a file or directory
class NetworkFileRenameRequested extends NetworkBrowsingEvent {
  final String oldPath;
  final String newName;

  const NetworkFileRenameRequested({
    required this.oldPath,
    required this.newName,
  });

  @override
  List<Object> get props => [oldPath, newName];
}

/// Event to clear the last successfully connected path from the state
class NetworkClearLastConnectedPath extends NetworkBrowsingEvent {
  const NetworkClearLastConnectedPath();

  @override
  List<Object?> get props => [];
}

/// Event to directly load a directory content (bypassing request)
/// This is useful for debugging or when implementing alternative loading methods
class NetworkDirectoryLoaded extends NetworkBrowsingEvent {
  final String path;
  final List<Directory> directories;
  final List<File> files;
  final bool isLoadingMore;
  final int requestId;

  const NetworkDirectoryLoaded({
    required this.path,
    required this.directories,
    required this.files,
    this.isLoadingMore = false,
    this.requestId = 0,
  });

  @override
  List<Object> get props =>
      [path, directories, files, isLoadingMore, requestId];
}

/// Event emitted by the BLoC when a directory listing failed in the background.
class NetworkDirectoryLoadFailed extends NetworkBrowsingEvent {
  final String path;
  final String errorMessage;
  final int requestId;

  const NetworkDirectoryLoadFailed({
    required this.path,
    required this.errorMessage,
    required this.requestId,
  });

  @override
  List<Object> get props => [path, errorMessage, requestId];
}
