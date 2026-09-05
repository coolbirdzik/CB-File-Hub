// For Uri encoding
import 'dart:io';
import 'network_service_base.dart';
import 'smb_service.dart'; // Reverted back to the original smb_service
import 'mobile_smb_service.dart'; // Mobile SMB service for Android/iOS
import 'ftp_service.dart';
import 'webdav_service.dart';

/// Registry for managing all network service providers
class NetworkServiceRegistry {
  static final NetworkServiceRegistry _instance = NetworkServiceRegistry._();

  factory NetworkServiceRegistry() => _instance;

  NetworkServiceRegistry._() {
    // Register all available services
    // Use MobileSMBService for mobile platforms, SMBService for desktop
    if (Platform.isAndroid || Platform.isIOS) {
      _registerService(MobileSMBService());
    } else {
      _registerService(SMBService()); // Original SMBService for Windows/Desktop
    }
    _registerService(FTPService());
    _registerService(WebDAVService());
  }

  final List<NetworkServiceBase> _services = [];
  // Key: The service's internal basePath (e.g., smb://host/share)
  // Value: The service instance
  final Map<String, NetworkServiceBase> _activeConnections = {};

  /// Register a new network service
  void _registerService(NetworkServiceBase service) {
    if (service.isAvailable()) {
      _services.add(service);
    }
  }

  /// Get all available network services
  List<NetworkServiceBase> get availableServices =>
      List.unmodifiable(_services);

  /// Get active connections
  Map<String, NetworkServiceBase> get activeConnections =>
      Map.unmodifiable(_activeConnections);

  /// Get a network service by name
  NetworkServiceBase? getServiceByName(String name) {
    try {
      return _services.firstWhere((service) => service.serviceName == name);
    } catch (_) {
      return null;
    }
  }

  /// Connect to a network location
  /// Returns a connection result and saves the connection with a unique ID
  Future<ConnectionResult> connect({
    required String serviceName,
    required String host, // For SMB, this might be host or host/share
    required String username,
    String? password,
    int? port,
    Map<String, dynamic>? additionalOptions,
  }) async {
    final service = getServiceByName(serviceName);
    if (service == null) {
      return ConnectionResult(
        success: false,
        errorMessage: 'Service not found: $serviceName',
      );
    }

    // The service.connect() method will establish the connection
    // and its ConnectionResult.connectedPath will be the service's internal base path (e.g., smb://host/share)
    final serviceConnectionResult = await service.connect(
      host: host, // SMBService will parse host/share from this
      username: username,
      password: password,
      port: port,
      additionalOptions: additionalOptions,
    );

    if (serviceConnectionResult.success &&
        serviceConnectionResult.connectedPath != null) {
      String serviceBasePath = serviceConnectionResult.connectedPath!;
      _activeConnections[serviceBasePath] =
          service; // Store with its native base path as key

      // Construct the tab-friendly path
      String type = service.serviceName.toUpperCase(); // SMB, FTP, WEBDAV

      // For FTP, always use encoded host format
      if (type == "FTP") {
        String hostComponent = Uri.encodeComponent(host);
        String tabPath = '#network/$type/$hostComponent/';
        return ConnectionResult(success: true, connectedPath: tabPath);
      }

      // Legacy format for other services
      Uri parsedBasePath = Uri.parse(serviceBasePath);
      String hostComponent = Uri.encodeComponent(parsedBasePath.host);

      // Đơn giản hóa đường dẫn tab
      String tabPath = '#network/$type/$hostComponent/';

      return ConnectionResult(
        success: true,
        connectedPath: tabPath, // Return the transformed #network/... path
      );
    } else {
      return serviceConnectionResult; // Return original error result
    }
  }

  /// Get a connected service by its path prefix
  NetworkServiceBase? getServiceForPath(String tabPath) {
    if (!tabPath.startsWith('#network/')) {
      return null;
    }

    final parts = tabPath.substring('#network/'.length).split('/');
    if (parts.length < 2) {
      return null; // Needs at least Type and Host
    }

    String serviceType = parts[0].toUpperCase(); // SMB, FTP, WEBDAV
    String hostComponent = Uri.decodeComponent(parts[1]);

    // For FTP connections, we need special handling
    if (serviceType == "FTP") {
      // Log all available FTP services for debugging
      bool anyFtpFound = false;
      for (var entry in _activeConnections.entries) {
        if (entry.value.serviceName.toUpperCase() == "FTP") {
          anyFtpFound = true;
        }
      }

      if (!anyFtpFound) {
        return null;
      }

      // Always return ANY FTP service since we handle paths internally
      for (var entry in _activeConnections.entries) {
        final service = entry.value;
        if (service.serviceName.toUpperCase() == "FTP") {
          return service;
        }
      }
    }
    // For other services, do standard matching
    else {
      for (var entry in _activeConnections.entries) {
        final serviceBasePath = entry.key;
        final service = entry.value;

        String serviceTypeInBasePath = "";
        if (serviceBasePath.contains("://")) {
          serviceTypeInBasePath = serviceBasePath.split("://")[0].toUpperCase();
        }

        String actualServiceName = service.serviceName.toUpperCase();
        bool typeMatches =
            serviceType == actualServiceName ||
            serviceType == serviceTypeInBasePath;

        bool hostMatches = false;
        if (serviceBasePath.contains(hostComponent)) {
          hostMatches = true;
        } else {
          // Try URI parsing for better host comparison
          try {
            final uri = Uri.tryParse(serviceBasePath);
            if (uri != null) {
              hostMatches =
                  uri.host == hostComponent ||
                  uri.host.contains(hostComponent) ||
                  hostComponent.contains(uri.host);
            }
          } catch (_) {}
        }

        // Special handling for SMB services without share in connectedPath
        // but with share in the requested path
        if (!hostMatches && serviceType == "SMB") {
          try {
            final uri = Uri.tryParse(serviceBasePath);
            if (uri != null) {
              if (uri.host == hostComponent) {
                // Host matches exactly, this is likely the right service
                // even if the share part doesn't match (share might be in the path)
                hostMatches = true;
              }
            }
          } catch (_) {}
        }

        if (typeMatches && hostMatches) {
          return service;
        }
      }
    }

    return null;
  }

  /// Disconnect from a specific network path
  Future<void> disconnect(String tabPath) async {
    // We need to find the original serviceBasePath from the tabPath to remove it
    final service = getServiceForPath(
      tabPath,
    ); // This should now correctly find the service
    if (service != null) {
      // Find the key (serviceBasePath) associated with this service instance IF NEEDED.
      // However, service.basePath should give the original key if service instances are unique per connection.
      // Let's assume service.basePath is the key used in _activeConnections.
      String? serviceKeyToRemove;
      _activeConnections.forEach((key, value) {
        if (value == service) {
          // relies on service instances being unique per active connection
          // A more robust way would be if getServiceForPath could also return the key it found.
          // For now, if SmbService holds its host/share, its basePath should be smb://host/share
          serviceKeyToRemove = key;
        }
      });

      if (serviceKeyToRemove != null) {
        await service.disconnect();
        _activeConnections.remove(serviceKeyToRemove);
      } else {
        // Fallback to use service.basePath
        await service.disconnect();
        _activeConnections.remove(service.basePath);
      }
    }
  }

  /// Disconnect from all network locations
  Future<void> disconnectAll() async {
    for (final service in _activeConnections.values) {
      await service.disconnect();
    }
    _activeConnections.clear();
  }

  /// Check if a path belongs to a network service
  bool isNetworkPath(String tabPath) {
    // First check the basic format condition
    if (!tabPath.startsWith('#network/')) {
      return false;
    }

    // Get the service type from the path
    final parts = tabPath.substring('#network/'.length).split('/');
    if (parts.isEmpty) {
      return false;
    }

    String serviceType = parts[0].toUpperCase();

    // For newly navigated paths that haven't connected yet, check if service type exists
    for (var service in _services) {
      if (service.serviceName.toUpperCase() == serviceType) {
        // Check if we're already connected to this service via getServiceForPath
        final connectedService = getServiceForPath(tabPath);
        if (connectedService != null) {
          return true;
        }

        // Service type exists but not connected yet - still a valid network path
        return true;
      }
    }

    // No matching service found
    return false;
  }

  // New utility method to get the tab path for a given native service path
  String? getTabPathForNativeServiceBasePath(String nativeServiceBasePath) {
    final service = _activeConnections[nativeServiceBasePath];
    if (service == null) return null;

    Uri parsedBasePath = Uri.parse(nativeServiceBasePath);
    String type = service.serviceName.toUpperCase(); // SMB, FTP, WEBDAV
    String hostComponent = Uri.encodeComponent(parsedBasePath.host);
    // Path component from the native base path (e.g., /share_name from smb://server/share_name)
    String pathSegment = parsedBasePath.path.startsWith('/')
        ? parsedBasePath.path.substring(1)
        : parsedBasePath.path;
    String encodedPathComponent = Uri.encodeComponent(pathSegment);

    String tabPath = '#network/$type/$hostComponent';
    if (encodedPathComponent.isNotEmpty) {
      // For SMB, the 'share' is part of the host in some contexts, but here it's part of the path from Uri.parse.
      // The S prefix helps distinguish this base path component from further subdirectories.
      tabPath += '/S$encodedPathComponent';
    }
    if (!tabPath.endsWith('/')) {
      tabPath += '/';
    }
    return tabPath;
  }
}
