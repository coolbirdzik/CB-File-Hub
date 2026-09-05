import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// A service for discovering network devices and services
class NetworkDiscoveryService {
  static const int _smbPort = 445; // Standard SMB port
  static const int _netbiosPort =
      139; // NetBIOS port used by older SMB implementations
  static const int _timeoutMilliseconds =
      100; // Reduced timeout for faster scanning
  static const int _maxConcurrentScans = 50; // Increased concurrency
  static const int _batchSize = 10; // Process hosts in smaller batches

  /// Singleton instance
  static final NetworkDiscoveryService _instance =
      NetworkDiscoveryService._internal();

  /// Factory constructor to return the singleton instance
  factory NetworkDiscoveryService() => _instance;

  /// Private constructor
  NetworkDiscoveryService._internal();

  /// Stream controller for discovered devices
  final StreamController<NetworkDevice> _deviceStreamController =
      StreamController<NetworkDevice>.broadcast();

  /// Stream of discovered devices
  Stream<NetworkDevice> get deviceStream => _deviceStreamController.stream;

  /// Status of the current scan
  bool _isScanning = false;

  /// Check if a scan is currently in progress
  bool get isScanning => _isScanning;

  /// List of discovered devices from the most recent scan
  final List<NetworkDevice> _discoveredDevices = [];

  /// Get the list of discovered devices
  List<NetworkDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  /// Dispose resources
  void dispose() {
    _deviceStreamController.close();
    debugPrint('NetworkDiscoveryService: Disposed resources');
  }

  /// Cache for recently discovered devices to avoid re-scanning
  final Map<String, NetworkDevice> _deviceCache = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// Scan the local network for SMB devices with real-time updates
  Future<List<NetworkDevice>> scanNetwork() async {
    if (_isScanning) {
      return _discoveredDevices; // Return current list if already scanning
    }

    _isScanning = true;
    _discoveredDevices.clear();
    final scannedSubnets = <String>{};

    try {
      // Get all local IP addresses from all network interfaces
      final localIps = await _getAllLocalIps();

      if (localIps.isEmpty) {
        _isScanning = false;
        return _discoveredDevices;
      }

      // Clean up expired cache entries
      _cleanupExpiredCache();

      for (final ip in localIps) {
        // Extract the subnet (e.g., from 192.168.1.5 to 192.168.1)
        final ipParts = ip.split('.');
        if (ipParts.length != 4) {
          continue; // Skip to the next IP
        }

        final subnet = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';

        // Check if this subnet has already been scanned
        if (scannedSubnets.contains(subnet)) {
          continue;
        }
        scannedSubnets.add(subnet);

        // Generate host list with optimized order (common ranges first)
        final List<String> hosts = _generateOptimizedHostList(subnet);

        // Process hosts with improved concurrency
        await _scanHostsOptimized(hosts);
      }
    } catch (e) {
      // Error during network scan
    } finally {
      _isScanning = false;
    }

    return _discoveredDevices;
  }

  /// Generate optimized host list with common ranges first
  List<String> _generateOptimizedHostList(String subnet) {
    final List<String> hosts = [];

    // Add common ranges first (1-50, 100-150, 200-254)
    // These ranges are more likely to contain devices
    for (int i = 1; i <= 50; i++) {
      hosts.add('$subnet.$i');
    }
    for (int i = 100; i <= 150; i++) {
      hosts.add('$subnet.$i');
    }
    for (int i = 200; i <= 254; i++) {
      hosts.add('$subnet.$i');
    }

    // Add remaining ranges
    for (int i = 51; i <= 99; i++) {
      hosts.add('$subnet.$i');
    }
    for (int i = 151; i <= 199; i++) {
      hosts.add('$subnet.$i');
    }

    return hosts;
  }

  /// Clean up expired cache entries
  void _cleanupExpiredCache() {
    final now = DateTime.now();
    _deviceCache.removeWhere((key, device) {
      // Remove entries older than cache expiry time
      return now.difference(device._discoveredAt) > _cacheExpiry;
    });
  }

  /// Optimized host scanning with better concurrency management
  Future<void> _scanHostsOptimized(List<String> hosts) async {
    int activeScans = 0;

    // Process hosts in batches for better performance
    for (int i = 0; i < hosts.length; i += _batchSize) {
      if (!_isScanning) break;

      final batchEnd = (i + _batchSize < hosts.length)
          ? i + _batchSize
          : hosts.length;
      final batch = hosts.sublist(i, batchEnd);

      // Wait if we've reached the maximum concurrent scans
      while (activeScans >= _maxConcurrentScans && _isScanning) {
        await Future.delayed(const Duration(milliseconds: 5));
      }

      if (!_isScanning) break;

      // Start batch of scans
      for (final host in batch) {
        if (!_isScanning) break;

        activeScans++;
        _scanHostFast(host).then((_) {
          activeScans--;
        });
      }

      // Small delay between batches to prevent overwhelming
      if (_isScanning) {
        await Future.delayed(const Duration(milliseconds: 2));
      }
    }

    // Wait for all remaining scans to complete
    while (activeScans > 0 && _isScanning) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Cancel an ongoing scan
  void cancelScan() {
    _isScanning = false;
  }

  /// Fast host scanning with minimal overhead
  Future<void> _scanHostFast(String host) async {
    if (!_isScanning) return;

    // Check cache first
    if (_deviceCache.containsKey(host)) {
      final cachedDevice = _deviceCache[host]!;
      if (DateTime.now().difference(cachedDevice._discoveredAt) <
          _cacheExpiry) {
        // Use cached device if not expired
        if (!_discoveredDevices.any((device) => device.ipAddress == host)) {
          _discoveredDevices.add(cachedDevice);
          _deviceStreamController.add(cachedDevice);
        }
        return;
      } else {
        // Remove expired cache entry
        _deviceCache.remove(host);
      }
    }

    // Try SMB port first with very short timeout
    bool isSmbPort = await _isPortOpenFast(host, _smbPort);

    // Only try NetBIOS if SMB port is closed and scan is still active
    bool isNetbiosPort = false;
    if (!isSmbPort && _isScanning) {
      isNetbiosPort = await _isPortOpenFast(host, _netbiosPort);
    }

    // If either port is open, add the device immediately
    if (isSmbPort || isNetbiosPort) {
      // Prevent adding duplicate devices
      if (_discoveredDevices.any((device) => device.ipAddress == host)) {
        return;
      }

      // Get hostname asynchronously without blocking
      _getHostnameAsync(host).then((deviceName) {
        // Create a better device name if hostname resolution failed
        String displayName;
        if (deviceName != null) {
          displayName = deviceName;
        } else {
          // Use a more descriptive name than just 'Unknown'
          displayName = 'SMB Server ($host)';
        }

        final device = NetworkDevice(
          ipAddress: host,
          name: displayName,
          type: NetworkDeviceType.smb,
          hasSmbPort: isSmbPort,
          hasNetbiosPort: isNetbiosPort,
        );

        // Cache the device
        _deviceCache[host] = device;

        // Add to list and emit for real-time updates
        if (!_discoveredDevices.any((d) => d.ipAddress == host)) {
          _discoveredDevices.add(device);
          _deviceStreamController.add(device);
        }
      });
    }
  }

  /// Fast port checking with minimal timeout
  Future<bool> _isPortOpenFast(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: _timeoutMilliseconds),
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Asynchronous hostname resolution with improved timeout and fallback
  Future<String?> _getHostnameAsync(String ipAddress) async {
    try {
      // Increase timeout for better results, especially on mobile networks
      final result = await InternetAddress(
        ipAddress,
      ).reverse().timeout(const Duration(milliseconds: 500));

      // If hostname is empty or just the IP address, return null to use fallback
      final hostname = result.host;
      if (hostname.isEmpty || hostname == ipAddress) {
        return null;
      }

      return hostname;
    } catch (e) {
      return null;
    }
  }

  /// Get all local IPv4 addresses from all available network interfaces.
  Future<List<String>> _getAllLocalIps() async {
    final List<String> ips = [];
    try {
      // Look for all non-loopback, non-link-local IPv4 addresses.
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          ips.add(addr.address);
        }
      }
    } catch (e) {
      // Error getting local IPs
    }
    return ips;
  }

  /// Clear the device cache
  void clearCache() {
    _deviceCache.clear();
  }

  /// Update SMB version for a specific device
  Future<void> updateSmbVersion(String ipAddress, String smbVersion) async {
    // Update in discovered devices list
    final deviceIndex = _discoveredDevices.indexWhere(
      (d) => d.ipAddress == ipAddress,
    );
    if (deviceIndex != -1) {
      final oldDevice = _discoveredDevices[deviceIndex];
      final updatedDevice = NetworkDevice(
        ipAddress: oldDevice.ipAddress,
        name: oldDevice.name,
        type: oldDevice.type,
        hasSmbPort: oldDevice.hasSmbPort,
        hasNetbiosPort: oldDevice.hasNetbiosPort,
        smbVersion: smbVersion,
      );
      _discoveredDevices[deviceIndex] = updatedDevice;

      // Update cache
      _deviceCache[ipAddress] = updatedDevice;

      // Emit updated device
      _deviceStreamController.add(updatedDevice);
    }
  }
}

/// Represents a discovered network device
class NetworkDevice {
  final String ipAddress;
  final String name;
  final NetworkDeviceType type;
  final bool hasSmbPort;
  final bool hasNetbiosPort;
  final String? smbVersion; // SMB version information
  final DateTime _discoveredAt;

  NetworkDevice({
    required this.ipAddress,
    required this.name,
    required this.type,
    this.hasSmbPort = false,
    this.hasNetbiosPort = false,
    this.smbVersion,
  }) : _discoveredAt = DateTime.now();

  @override
  String toString() {
    return '$name ($ipAddress)';
  }
}

/// Types of network devices
enum NetworkDeviceType { smb, ftp, webdav, unknown }
