import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
// Aliased to avoid conflict with 'path' in _openSavedConnection
import 'package:url_launcher/url_launcher.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
import '../../../services/network_browsing/network_discovery_service.dart';
import '../../../services/network_browsing/network_service_registry.dart'; // Added import for registry
import '../../../services/network_browsing/mobile_smb_service.dart'; // Added import for mobile SMB service
import '../../tab_manager/core/tab_manager.dart';
import '../../utils/fluent_background.dart';
import '../system_screen.dart';
import 'network_connection_dialog.dart';

/// Screen to browse SMB servers in the local network
class SMBBrowserScreen extends StatefulWidget {
  /// The tab ID this screen belongs to
  final String tabId;

  const SMBBrowserScreen({
    Key? key,
    required this.tabId,
  }) : super(key: key);

  @override
  State<SMBBrowserScreen> createState() => _SMBBrowserScreenState();
}

class _SMBBrowserScreenState extends State<SMBBrowserScreen>
    with AutomaticKeepAliveClientMixin {
  final NetworkDiscoveryService _discoveryService = NetworkDiscoveryService();
  final NetworkServiceRegistry _registry =
      NetworkServiceRegistry(); // Added registry instance

  // Sử dụng static cache để giữ state khi widget bị dispose
  static final List<NetworkDevice> _cachedDiscoveredDevices = [];
  static bool _cachedHasScanned = false;
  static bool _cachedIsScanning = false;

  final List<NetworkDevice> _discoveredDevices = [];
  bool _isScanning = false;
  bool _hasScanned = false; // Thêm flag để track đã scan chưa
  bool _showScanPermissionWarning = false;
  StreamSubscription<NetworkDevice>? _deviceStreamSubscription;

  // Thêm bloc local để không phụ thuộc vào context
  late NetworkBrowsingBloc _networkBloc;
  bool _isLocalBloc = false;

  // SMB version tracking
  String _smbVersion = 'Unknown';
  String _connectionInfo = 'Not connected';
  bool _isLoadingVersion = false;

  // AutomaticKeepAliveClientMixin implementation
  @override
  bool get wantKeepAlive => true;

  // Method để sync state với cache
  void _syncStateWithCache() {
    _isScanning = _cachedIsScanning;
    _hasScanned = _cachedHasScanned;
    _discoveredDevices.clear();
    _discoveredDevices.addAll(_cachedDiscoveredDevices);
  }

  // Method để update cache từ current state
  void _updateCacheFromState() {
    _cachedIsScanning = _isScanning;
    _cachedHasScanned = _hasScanned;
    _cachedDiscoveredDevices.clear();
    _cachedDiscoveredDevices.addAll(_discoveredDevices);
  }

  @override
  void initState() {
    super.initState();

    // Restore cached state
    _syncStateWithCache();

    // Thử lấy bloc từ context hoặc tạo mới nếu không tìm thấy
    try {
      _networkBloc =
          BlocProvider.of<NetworkBrowsingBloc>(context, listen: false);
      _isLocalBloc = false;
    } catch (e) {
      debugPrint(
          'NetworkBrowsingBloc không tìm thấy trong context, tạo mới: $e');
      _networkBloc = NetworkBrowsingBloc();
      _isLocalBloc = true;
    }

    _checkNetworkDiscovery();

    // Thêm listener để refresh UI khi có connection mới
    _networkBloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          // Force rebuild để cập nhật active connections
        });
        // Update SMB version info when connections change
        _updateSmbVersionInfo();
      }
    });

    // Update SMB version info on init
    _updateSmbVersionInfo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync state với cache khi dependencies thay đổi
    _syncStateWithCache();
  }

  @override
  void dispose() {
    // Đảm bảo đóng bloc nếu là local
    if (_isLocalBloc) {
      _networkBloc.close();
    }

    // Ensure we stop any ongoing network scan
    _discoveryService.cancelScan();
    _deviceStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkNetworkDiscovery() async {
    // Mặc định hiển thị cảnh báo trên Windows vì thường phải bật Network Discovery
    if (Platform.isWindows) {
      setState(() {
        _showScanPermissionWarning = true;
      });
    }

    // Chỉ scan nếu chưa scan bao giờ
    if (!_hasScanned) {
      _startNetworkScan();
    }
  }

  Future<void> _startNetworkScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      // Chỉ clear devices nếu đây là lần scan đầu tiên hoặc manual refresh
      if (!_hasScanned) {
        _discoveredDevices.clear();
        _cachedDiscoveredDevices.clear();
      }
      _updateCacheFromState();
    });

    // Subscribe to device stream for real-time updates
    _deviceStreamSubscription?.cancel();
    _deviceStreamSubscription = _discoveryService.deviceStream.listen((device) {
      if (mounted) {
        setState(() {
          // Add device if not already in list
          if (!_discoveredDevices.any((d) => d.ipAddress == device.ipAddress)) {
            _discoveredDevices.add(device);
            _cachedDiscoveredDevices.add(device);
          }
        });
      }
    });

    try {
      // Start the scan - devices will be added to the list via stream
      await _discoveryService.scanNetwork();

      if (mounted) {
        setState(() {
          _isScanning = false;
          _hasScanned = true; // Đánh dấu đã scan
          _updateCacheFromState();
        });

        // Start SMB version detection for discovered devices
        _detectSmbVersionsForDevices();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _updateCacheFromState();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${AppLocalizations.of(context)!.networkScanFailed}: $e')),
        );
      }
    } finally {
      _deviceStreamSubscription?.cancel();
    }
  }

  // Method để reset scan state và scan lại từ đầu
  Future<void> _resetAndScan() async {
    setState(() {
      _hasScanned = false;
      _discoveredDevices.clear();
      _cachedDiscoveredDevices.clear();
      _updateCacheFromState();
    });
    await _startNetworkScan();
  }

  /// Get SMB version and connection info for display
  Future<void> _updateSmbVersionInfo() async {
    if (_isLoadingVersion) return;

    setState(() {
      _isLoadingVersion = true;
    });

    try {
      // Get SMB service from registry
      final smbService = _registry.getServiceByName('SMB');
      if (smbService != null && smbService is MobileSMBService) {
        // Try to get SMB version from mobile service
        final version = await smbService.getSmbVersion();
        final info = await smbService.getConnectionInfo();

        if (mounted) {
          setState(() {
            _smbVersion = version;
            _connectionInfo = info;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to get SMB version info: $e');
      if (mounted) {
        setState(() {
          _smbVersion = AppLocalizations.of(context)!.smbVersionUnknown;
          _connectionInfo =
              AppLocalizations.of(context)!.connectionInfoUnavailable;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
    }
  }

  /// Detect SMB versions for discovered devices
  Future<void> _detectSmbVersionsForDevices() async {
    if (_discoveredDevices.isEmpty) return;

    try {
      for (final device in _discoveredDevices) {
        // Try to detect SMB version for each device
        // This is a placeholder implementation
        // In a real implementation, you would attempt to connect to each device
        // and determine its SMB version
        debugPrint('Detecting SMB version for device: ${device.name}');
      }
    } catch (e) {
      debugPrint('Error detecting SMB versions: $e');
    }
  }

  Future<void> _openWindowsNetworkSettings() async {
    // Mở cài đặt Network Discovery trên Windows
    if (Platform.isWindows) {
      // Pre-extract context-dependent values before async gaps
      final l10n = AppLocalizations.of(context)!;
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      try {
        bool opened = false;

        // Phương pháp 1: Sử dụng url_launcher để mở URI ms-settings
        try {
          final Uri settingsUri = Uri.parse('ms-settings:network');
          if (await canLaunchUrl(settingsUri)) {
            await launchUrl(settingsUri);
            opened = true;
            debugPrint('Successfully opened ms-settings:network');
          }
        } catch (e) {
          debugPrint('Failed to launch ms-settings:network: $e');
        }

        if (!opened) {
          // Phương pháp 2: Mở Internet Settings Control Panel
          try {
            await Process.run(
                'rundll32.exe', ['shell32.dll,Control_RunDLL', 'ncpa.cpl']);
            opened = true;
            debugPrint('Successfully opened network connections');
          } catch (e) {
            debugPrint('Failed to open ncpa.cpl: $e');
          }
        }

        if (!opened) {
          // Phương pháp 3: Thử shell execute với explorer
          try {
            await Process.run('explorer.exe', [
              'shell:::{26EE0668-A00A-44D7-9371-BEB064C98683}\\0\\::{7007ACC7-3202-11D1-AAD2-00805FC1270E}'
            ]);
            opened = true;
            debugPrint('Successfully opened network shell');
          } catch (e) {
            debugPrint('Failed to open shell: $e');
          }
        }

        if (!opened) {
          // Phương pháp 4: Thử mở với cmd
          try {
            await Process.run(
                'cmd.exe', ['/c', 'start', 'control', 'ncpa.cpl']);
            opened = true;
            debugPrint('Successfully opened ncpa.cpl through cmd');
          } catch (e) {
            debugPrint('Failed to open through cmd: $e');
          }
        }

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(opened
                ? l10n.networkSettingsOpened
                : l10n.cannotOpenNetworkSettings),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        debugPrint('Error opening network settings: $e');
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(l10n.errorWithMessage(e.toString()))),
        );
      }
    }
  }

  void _connectToSMBServer(String ipAddress, String deviceName) {
    // Lấy TabManagerBloc từ context trước khi mở dialog
    final tabBloc = BlocProvider.of<TabManagerBloc>(context, listen: false);

    showDialog<String?>(
      context: context,
      builder: (context) => NetworkConnectionDialog(
        initialService: 'SMB',
        initialHost: ipAddress,
        onConnectionRequested: (connectionPath, tabName) {
          if (connectionPath.startsWith('#network/')) {
            debugPrint(
                'Opening SMB connection in tab with path: $connectionPath');

            tabBloc.add(UpdateTabPath(widget.tabId, connectionPath));
            tabBloc.add(UpdateTabName(widget.tabId, tabName));
          } else {
            // Handle cases where connectionPath is null (dialog cancelled) or not the expected format
            debugPrint(
                'SMBBrowserScreen: Received unexpected connection path: $connectionPath');
          }
        },
      ),
    );
  }

  void _openSavedConnection(String nativeServicePath) {
    // nativeServicePath is like smb://host/share
    final String? tabPath =
        _registry.getTabPathForNativeServiceBasePath(nativeServicePath);

    if (tabPath != null) {
      final tabBloc = BlocProvider.of<TabManagerBloc>(context, listen: false);
      // Derive a user-friendly name for the tab from the native path
      String tabName = 'SMB Share';
      try {
        Uri parsedNativePath = Uri.parse(nativeServicePath);
        String host = parsedNativePath.host;
        String sharePath = parsedNativePath.path.startsWith('/')
            ? parsedNativePath.path.substring(1)
            : parsedNativePath.path;
        tabName = sharePath.isNotEmpty ? '$host/$sharePath' : host;
      } catch (_) {
        // use default name if parsing fails
      }

      debugPrint('Opening saved SMB connection in tab with path: $tabPath');
      tabBloc.add(UpdateTabPath(widget.tabId, tabPath));
      tabBloc.add(UpdateTabName(widget.tabId, tabName));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Call super.build to ensure keepAlive is managed
    final l10n = AppLocalizations.of(context)!;
    return SystemScreen(
      title: l10n.smbNetwork,
      systemId: '#smb',
      icon: PhosphorIconsLight.desktop,
      showAppBar: true,
      actions: [
        IconButton(
          icon: _isScanning
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.onPrimary),
                  ),
                )
              : const Icon(PhosphorIconsLight.arrowsClockwise),
          onPressed: _isScanning ? null : _resetAndScan,
          tooltip: l10n.refresh,
        ),
        IconButton(
          icon: const Icon(PhosphorIconsLight.plus),
          onPressed: () {
            // Lấy TabManagerBloc từ context trước khi mở dialog
            final tabBloc =
                BlocProvider.of<TabManagerBloc>(context, listen: false);

            // Hiển thị dialog kết nối mới
            showDialog<String?>(
              context: context,
              builder: (dialogContext) => NetworkConnectionDialog(
                initialService: 'SMB',
                onConnectionRequested: (connectionPath, tabName) {
                  if (connectionPath.startsWith('#network/')) {
                    debugPrint(
                        'Opening new SMB connection in tab with path: $connectionPath');
                    tabBloc.add(UpdateTabPath(widget.tabId, connectionPath));
                    tabBloc.add(UpdateTabName(widget.tabId, tabName));
                  }
                },
              ),
            );
          },
          tooltip: l10n.addConnection,
        ),
      ],
      child: BlocProvider.value(
        value: _networkBloc,
        child: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
          bloc: _networkBloc,
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hiển thị cảnh báo bật Network Discovery nếu cần
                if (_showScanPermissionWarning)
                  FluentBackground(
                    blurAmount: 8.0,
                    opacity: 0.7,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(PhosphorIconsLight.warning,
                              color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.networkDiscoveryDisabled,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  l10n.networkDiscoveryDescription,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _openWindowsNetworkSettings,
                            child: Text(l10n.openSettings),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Connections Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.activeConnectionsTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        l10n.activeConnectionsDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      // SMB Version Info
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsLight.info,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${l10n.smbVersion}: $_smbVersion',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  if (_connectionInfo != l10n.notConnected)
                                    Text(
                                      _connectionInfo,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (_isLoadingVersion)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              IconButton(
                                icon: const Icon(
                                    PhosphorIconsLight.arrowsClockwise,
                                    size: 16),
                                onPressed: _updateSmbVersionInfo,
                                tooltip: l10n.refreshSmbVersionInfo,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Active connections list
                _buildActiveConnections(state.connections),

                const Divider(height: 32),

                // Discovered Devices Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.discoveredSmbServers,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        l10n.discoveredSmbServersDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                // Discovered devices list
                _buildDiscoveredDevices(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildActiveConnections(Map<String, dynamic>? connections) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final activeConnections = _registry.activeConnections;

    debugPrint(
        'SMBBrowserScreen: Active connections from registry: ${activeConnections.keys}');

    final smbConnections = activeConnections.entries
        .where((entry) => entry.key.startsWith('smb://'))
        .toList();

    debugPrint(
        'SMBBrowserScreen: SMB connections found: ${smbConnections.length}');

    if (smbConnections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsLight.info,
                  color: theme.colorScheme.onSurfaceVariant, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.noActiveSmbConnections,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      l10n.connectToSmbServer,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: smbConnections.length,
      itemBuilder: (context, index) {
        final entry = smbConnections[index];
        final path = entry.key;

        // Extract server name from path
        final serverName = path.replaceFirst('smb://', '').split('/').first;
        final sharePath = path.replaceFirst('smb://$serverName/', '');

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(PhosphorIconsLight.desktop,
                  color: theme.colorScheme.primary, size: 20),
            ),
            title: Text(
              serverName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sharePath.isNotEmpty
                      ? l10n.shareLabel(sharePath)
                      : l10n.rootShare,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Text(
                    l10n.connected,
                    style: TextStyle(
                        fontSize: 10, color: theme.colorScheme.tertiary),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(PhosphorIconsLight.arrowRight,
                      color: theme.colorScheme.primary),
                  onPressed: () => _openSavedConnection(path),
                  tooltip: l10n.openConnection,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.xCircle,
                      color: theme.colorScheme.error),
                  onPressed: () {
                    _networkBloc.add(NetworkDisconnectRequested(path));
                  },
                  tooltip: l10n.disconnect,
                ),
              ],
            ),
            onTap: () => _openSavedConnection(path),
          ),
        );
      },
    );
  }

  Widget _buildDiscoveredDevices() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (_discoveredDevices.isEmpty) {
      if (_isScanning) {
        return Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.scanningForSmbServers,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.devicesWillAppear,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.scanningMayTakeTime,
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (_hasScanned) {
        return Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsLight.wifiSlash,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(l10n.noSmbServersFound),
                  const SizedBox(height: 8),
                  Text(
                    l10n.tryScanningAgain,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _resetAndScan,
                    icon: const Icon(PhosphorIconsLight.arrowsClockwise,
                        size: 16),
                    label: Text(l10n.scanAgain),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsLight.magnifyingGlass,
                    size: 48, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(l10n.readyToScan),
                const SizedBox(height: 8),
                Text(
                  l10n.clickRefreshToScan,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _resetAndScan,
                  icon:
                      const Icon(PhosphorIconsLight.arrowsClockwise, size: 16),
                  label: Text(l10n.startScan),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Text(
                  l10n.foundDevicesCount(_discoveredDevices.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (_isScanning)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.scanning,
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.primary),
                      ),
                    ],
                  )
                else if (_hasScanned)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Text(
                      l10n.scanComplete,
                      style: TextStyle(
                          fontSize: 10, color: theme.colorScheme.tertiary),
                    ),
                  ),
              ],
            ),
          ),

          // Device list
          Expanded(
            child: ListView.builder(
              itemCount: _discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = _discoveredDevices[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 4.0),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(PhosphorIconsLight.desktop,
                          color: theme.colorScheme.primary, size: 20),
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.ipAddress,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (device.hasSmbPort || device.hasNetbiosPort)
                          Row(
                            children: [
                              if (device.hasSmbPort)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.tertiary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16.0),
                                  ),
                                  child: Text(
                                    'SMB',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: theme.colorScheme.tertiary),
                                  ),
                                ),
                              if (device.hasSmbPort && device.hasNetbiosPort)
                                const SizedBox(width: 4),
                              if (device.hasNetbiosPort)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16.0),
                                  ),
                                  child: Text(
                                    'NetBIOS',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: theme.colorScheme.secondary),
                                  ),
                                ),
                            ],
                          ),
                        if (device.smbVersion != null)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Text(
                              'SMB ${device.smbVersion}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.primary),
                            ),
                          ),
                      ],
                    ),
                    trailing: Icon(PhosphorIconsLight.arrowRight,
                        color: theme.colorScheme.primary),
                    onTap: () =>
                        _connectToSMBServer(device.ipAddress, device.name),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
