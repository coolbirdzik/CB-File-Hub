import 'dart:io';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/network_browsing/network_service_base.dart';
import '../../services/network_browsing/network_service_registry.dart';
import '../../helpers/network/network_thumbnail_helper.dart';
import '../../ui/widgets/thumbnail_loader.dart';
import '../../utils/app_logger.dart';
import '../../services/network_browsing/mobile_smb_service.dart';
import 'network_browsing_event.dart';
import 'network_browsing_state.dart';

/// BLoC for managing network browsing state
class NetworkBrowsingBloc
    extends Bloc<NetworkBrowsingEvent, NetworkBrowsingState> {
  final NetworkServiceRegistry _registry = NetworkServiceRegistry();

  int _directoryRequestId = 0;
  int _activeDirectoryRequestId = 0;

  // Toggle this to true if you need verbose BLoC logs for debugging.
  static const bool _enableBlocVerboseLogs = false;

  void _log(String message) {
    if (_enableBlocVerboseLogs) {
      AppLogger.debug(message);
    }
  }

  NetworkBrowsingBloc() : super(const NetworkBrowsingState.initial()) {
    on<NetworkServicesListRequested>(_onServicesListRequested);
    on<NetworkConnectionRequested>(_onConnectionRequested);
    on<NetworkDisconnectRequested>(_onDisconnectRequested);
    on<NetworkDirectoryRequested>(_onDirectoryRequested);
    on<NetworkClearLastConnectedPath>(_onClearLastConnectedPath);
    on<NetworkDirectoryLoaded>(_onDirectoryLoaded);
    on<NetworkDirectoryLoadFailed>(_onDirectoryLoadFailed);
  }

  void _onServicesListRequested(
    NetworkServicesListRequested event,
    Emitter<NetworkBrowsingState> emit,
  ) {
    emit(state.copyWith(isLoading: true));

    final services = _registry.availableServices;

    emit(
      state.copyWith(
        isLoading: false,
        services: services,
        clearServices: false,
      ),
    );
  }

  Future<void> _onConnectionRequested(
    NetworkConnectionRequested event,
    Emitter<NetworkBrowsingState> emit,
  ) async {
    emit(
      state.copyWith(
        isConnecting: true,
        clearLastSuccessfullyConnectedPath: true,
        clearErrorMessage: true,
      ),
    );

    try {
      final result = await _registry.connect(
        serviceName: event.serviceName,
        host: event.host,
        username: event.username,
        password: event.password,
        port: event.port,
        additionalOptions: event.additionalOptions,
      );

      if (result.success && result.connectedPath != null) {
        final service = _registry.getServiceByName(event.serviceName);
        if (service == null) {
          emit(
            state.copyWith(
              isConnecting: false,
              errorMessage:
                  'Service ${event.serviceName} not found after connection.',
              clearLastSuccessfullyConnectedPath: true,
            ),
          );
          return;
        }

        Map<String, NetworkServiceBase> updatedConnections =
            Map<String, NetworkServiceBase>.from(state.connections);
        updatedConnections[result.connectedPath!] = service;

        emit(
          state.copyWith(
            isConnecting: false,
            connections: updatedConnections,
            lastSuccessfullyConnectedPath: result.connectedPath,
            clearErrorMessage: true,
          ),
        );

        // Reset failed attempts when successfully connected
        NetworkThumbnailHelper.resetFailedAttempts();
        ThumbnailLoader.resetFailedAttempts();
      } else {
        emit(
          state.copyWith(
            isConnecting: false,
            errorMessage:
                result.errorMessage ?? 'Unknown error connecting to service',
            clearLastSuccessfullyConnectedPath: true,
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          isConnecting: false,
          errorMessage: 'Error connecting to service: $e',
          clearLastSuccessfullyConnectedPath: true,
        ),
      );
    }
  }

  Future<void> _onDirectoryRequested(
    NetworkDirectoryRequested event,
    Emitter<NetworkBrowsingState> emit,
  ) async {
    final int requestId = ++_directoryRequestId;
    _activeDirectoryRequestId = requestId;

    final NetworkServiceBase? service = _registry.getServiceForPath(event.path);
    if (service == null) {
      emit(
        state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          errorMessage: 'No connected service found for path: ${event.path}',
          currentPath: event.path,
          clearDirectories: true,
          clearFiles: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isLoading: true,
        isLoadingMore: false,
        currentService: service,
        currentPath: event.path,
        clearDirectories: true,
        clearFiles: true,
        clearErrorMessage: true,
      ),
    );

    // Yield to the UI thread before starting potentially slow network I/O.
    await Future<void>.delayed(Duration.zero);

    unawaited(
      _loadDirectoryInBackground(
        requestId: requestId,
        path: event.path,
        service: service,
      ),
    );
  }

  Future<void> _loadDirectoryInBackground({
    required int requestId,
    required String path,
    required NetworkServiceBase service,
  }) async {
    try {
      final Duration timeout = (Platform.isAndroid || Platform.isIOS)
          ? const Duration(seconds: 12)
          : const Duration(seconds: 8);

      List<FileSystemEntity> contents;
      try {
        contents = await service.listDirectory(path).timeout(timeout);
      } on TimeoutException catch (e) {
        // Best-effort reconnect for Mobile SMB on timeout.
        if (service is MobileSMBService) {
          try {
            await service.reconnect();
            contents = await service.listDirectory(path).timeout(timeout);
          } catch (_) {
            throw e;
          }
        } else {
          rethrow;
        }
      }

      if (requestId != _activeDirectoryRequestId) return;

      final validContents =
          contents.where((item) => item.path.isNotEmpty).toList();
      final List<Directory> directories = <Directory>[];
      final List<File> files = <File>[];

      const int firstBatchSize = 12;
      const int batchSize = 30;
      int processedCount = 0;

      for (final item in validContents) {
        if (item is Directory) {
          directories.add(item);
        } else if (item is File) {
          files.add(item);
        } else if (item.path.endsWith('/') || item.path.endsWith('\\')) {
          directories.add(Directory(item.path));
        } else {
          files.add(File(item.path));
        }

        processedCount++;

        final bool shouldEmitFirstBatch = processedCount == firstBatchSize &&
            processedCount < validContents.length;
        final bool shouldEmitBatch = processedCount % batchSize == 0 &&
            processedCount < validContents.length;

        if (shouldEmitFirstBatch || shouldEmitBatch) {
          add(
            NetworkDirectoryLoaded(
              path: path,
              directories: List<Directory>.from(directories),
              files: List<File>.from(files),
              isLoadingMore: true,
              requestId: requestId,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          if (requestId != _activeDirectoryRequestId) return;
        }
      }

      add(
        NetworkDirectoryLoaded(
          path: path,
          directories: directories,
          files: files,
          isLoadingMore: false,
          requestId: requestId,
        ),
      );
    } catch (e) {
      if (requestId != _activeDirectoryRequestId) return;
      add(
        NetworkDirectoryLoadFailed(
          path: path,
          errorMessage: 'Error listing directory: $e',
          requestId: requestId,
        ),
      );
    }
  }

  Future<void> _onDisconnectRequested(
    NetworkDisconnectRequested event,
    Emitter<NetworkBrowsingState> emit,
  ) async {
    final String servicePath = event.path;

    _log("NetworkBrowsingBloc: Disconnecting from path: $servicePath");
    _log(
      "NetworkBrowsingBloc: Current connections: ${state.connections.keys.join(', ')}",
    );

    if (!servicePath.startsWith('#network/')) {
      emit(state.copyWith(errorMessage: 'Invalid network path'));
      return;
    }

    try {
      // Lấy đường dẫn gốc để đóng kết nối vật lý
      await _registry.disconnect(servicePath);

      // Xóa kết nối khỏi danh sách
      final Map<String, NetworkServiceBase> updatedConnections = {
        ...state.connections,
      };

      // Xóa chính xác tab path khỏi danh sách
      final NetworkServiceBase? service = updatedConnections.remove(
        servicePath,
      );

      _log(
        "NetworkBrowsingBloc: Removed connection: $servicePath, service: ${service?.serviceName}",
      );
      _log(
        "NetworkBrowsingBloc: Updated connections: ${updatedConnections.keys.join(', ')}",
      );

      // Nếu ngắt kết nối dịch vụ hiện tại, reset về danh sách dịch vụ
      if (state.currentService != null &&
          state.currentPath != null &&
          state.currentPath!.startsWith(servicePath)) {
        emit(
          NetworkBrowsingState.disconnected(
            connections: updatedConnections,
            lastSuccessfullyConnectedPath: state.lastSuccessfullyConnectedPath,
            services: state.services,
          ),
        );
      } else {
        // Otherwise just update the connections map
        emit(state.copyWith(connections: updatedConnections));
      }
    } catch (e) {
      _log("NetworkBrowsingBloc: Error disconnecting: $e");
      emit(state.copyWith(errorMessage: 'Error disconnecting: $e'));
    }
  }

  void _onClearLastConnectedPath(
    NetworkClearLastConnectedPath event,
    Emitter<NetworkBrowsingState> emit,
  ) {
    emit(state.copyWith(clearLastSuccessfullyConnectedPath: true));
  }

  // Handler for the NetworkDirectoryLoaded event
  void _onDirectoryLoaded(
    NetworkDirectoryLoaded event,
    Emitter<NetworkBrowsingState> emit,
  ) {
    _log("NetworkBrowsingBloc: Processing NetworkDirectoryLoaded event");
    _log("NetworkBrowsingBloc: Path: ${event.path}");
    _log("NetworkBrowsingBloc: Directories: ${event.directories.length}");
    _log("NetworkBrowsingBloc: Files: ${event.files.length}");

    if (event.requestId != 0 && event.requestId != _activeDirectoryRequestId) {
      return;
    }

    // We simply update the state with the provided directories and files.
    emit(
      state.copyWith(
        isLoading: false,
        isLoadingMore: event.isLoadingMore,
        currentPath: event.path,
        directories: event.directories,
        files: event.files,
        clearErrorMessage: true,
        clearDirectories: false,
        clearFiles: false,
      ),
    );
  }

  void _onDirectoryLoadFailed(
    NetworkDirectoryLoadFailed event,
    Emitter<NetworkBrowsingState> emit,
  ) {
    if (event.requestId != _activeDirectoryRequestId) {
      return;
    }

    emit(
      state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        currentPath: event.path,
        errorMessage: event.errorMessage,
        clearDirectories: true,
        clearFiles: true,
      ),
    );
  }
}
