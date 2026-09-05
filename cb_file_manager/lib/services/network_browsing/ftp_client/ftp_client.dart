import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ftp_response.dart';
import 'ftp_file_info.dart';
import 'ftp_commands.dart';

/// A custom FTP client implementation that handles all basic FTP operations
class FtpClient {
  // Connection settings
  final String _host;
  final int _port;
  final String? _username;
  final String? _password;

  // Connection state
  Socket? _controlSocket;
  Socket? _dataSocket;
  ServerSocket? _passiveServer;
  bool _isConnected = false;
  bool _usePassiveMode = true; // Default to passive mode
  String? _currentDirectory;

  // Stream controller for command responses
  final StreamController<FtpResponse> _responseController =
      StreamController<FtpResponse>();

  // Completer for the current command
  Completer<FtpResponse>? _commandCompleter;

  /// Creates a new FTP client instance
  FtpClient({
    required this._host,
    this._port = 21,
    String this._username = 'anonymous',
    String this._password = 'anonymous@',
  });

  /// Returns true if connected to the server
  bool get isConnected => _isConnected;

  /// Returns the current working directory
  String? get currentDirectory => _currentDirectory;

  /// Connects to the FTP server and performs authentication
  Future<bool> connect() async {
    try {
      // Connect to the control socket
      _controlSocket = await Socket.connect(_host, _port);

      // Set up data handling
      _controlSocket!.listen(
        _handleControlResponse,
        onError: _handleControlError,
        onDone: _handleControlDone,
      );

      // Wait for server ready response (220)
      final response = await _waitForResponse();
      if (response.code != 220) {
        throw Exception('Failed to connect to FTP server: ${response.message}');
      }

      // Login with credentials
      await _sendCommand(FtpCommands.user(_username ?? 'anonymous'));
      final userResponse = await _waitForResponse();

      if (userResponse.code == 230) {
        // Already logged in, no password needed
        _isConnected = true;
        return true;
      }

      if (userResponse.code != 331) {
        throw Exception('Failed to send username: ${userResponse.message}');
      }

      await _sendCommand(FtpCommands.pass(_password ?? 'anonymous@'));
      final passResponse = await _waitForResponse();

      if (passResponse.code != 230) {
        throw Exception('Failed to authenticate: ${passResponse.message}');
      }

      // Set binary mode for file transfers
      await _sendCommand(FtpCommands.type('I'));
      final typeResponse = await _waitForResponse();

      if (typeResponse.code != 200) {
        throw Exception('Failed to set binary mode: ${typeResponse.message}');
      }

      // Get current directory
      await _updateCurrentDirectory();

      _isConnected = true;
      return true;
    } catch (e) {
      _handleError('Connection error: $e');
      await disconnect();
      return false;
    }
  }

  /// Disconnects from the FTP server
  Future<void> disconnect() async {
    _isConnected = false;

    try {
      if (_controlSocket != null) {
        await _sendCommand(FtpCommands.quit());
        await _controlSocket!.close();
        _controlSocket = null;
      }
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _responseController.close();
    debugPrint('FTPClient: Disposed resources');
  }

  /// Sends a NOOP command to keep the connection alive
  Future<void> sendNoop() async {
    if (!_isConnected) {
      debugPrint("FTPClient: Not connected, skipping NOOP.");
      return;
    }

    try {
      await _sendCommand(FtpCommands.noop());
      final response = await _waitForResponse();
      if (response.code != 200) {
        throw Exception('NOOP command failed: ${response.message}');
      }
      debugPrint("FTPClient: NOOP command successful.");
    } catch (e) {
      debugPrint("FTPClient: NOOP command failed with error: $e");
      // If NOOP fails, the connection is likely dead. The state is already
      // handled by the socket error handlers, which call _handleError.
      // We just need to rethrow to notify the caller (FTPService).
      rethrow;
    }
  }

  /// Lists files and directories in the specified path
  Future<List<FtpFileInfo>> listDirectory([String? path]) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    // Change directory if path is specified
    if (path != null && path != _currentDirectory) {
      await changeDirectory(path);
    }

    // Prepare data connection
    await _setupDataConnection();

    // Send LIST command with options for detailed listing
    debugPrint("FTP: Sending LIST command for directory: $_currentDirectory");
    await _sendCommand(FtpCommands.list());
    final listResponse = await _waitForResponse();

    if (listResponse.code != 150 && listResponse.code != 125) {
      throw Exception('Failed to list directory: ${listResponse.message}');
    }

    // Read directory listing
    final List<int> rawData = [];
    try {
      await for (final data in _dataSocket!) {
        rawData.addAll(data);
      }
      debugPrint(
        "FTP: Received ${rawData.length} bytes of directory listing data",
      );
    } catch (e) {
      debugPrint("FTP: Error reading data from socket: $e");
    }

    // Close data connection
    await _closeDataConnection();

    // Wait for transfer complete message
    final transferResponse = await _waitForResponse();
    if (transferResponse.code != 226) {
      throw Exception(
        'Failed to complete directory listing: ${transferResponse.message}',
      );
    }

    // Parse directory listing
    String listing = "";
    try {
      listing = utf8.decode(rawData);
    } catch (e) {
      // Try alternate encoding if UTF-8 fails
      try {
        listing = latin1.decode(rawData);
      } catch (e2) {
        debugPrint("FTP: Error decoding directory listing: $e2");
      }
    }

    // Trim whitespace and remove empty lines
    listing = listing.trim();

    // Log the raw listing for debugging
    debugPrint("FTP: Raw directory listing:\n$listing");

    // Skip processing if the listing is completely empty
    if (listing.isEmpty) {
      debugPrint("FTP: Directory listing is empty");
      return [];
    }

    // If listing seems to contain only whitespace or invalid lines, try NLST command as fallback
    if (listing.split('\n').every((line) => line.trim().isEmpty)) {
      debugPrint(
        "FTP: LIST returned only empty lines, trying NLST as fallback",
      );

      // Setup new data connection
      await _setupDataConnection();

      // Send NLST command
      await _sendCommand(FtpCommands.nlst());
      final nlstResponse = await _waitForResponse();

      if (nlstResponse.code != 150 && nlstResponse.code != 125) {
        throw Exception(
          'Failed to list directory with NLST: ${nlstResponse.message}',
        );
      }

      // Read NLST data
      final List<int> nlstRawData = [];
      await for (final data in _dataSocket!) {
        nlstRawData.addAll(data);
      }

      // Close data connection
      await _closeDataConnection();

      // Wait for transfer complete
      final nlstTransferResponse = await _waitForResponse();
      if (nlstTransferResponse.code != 226) {
        throw Exception(
          'Failed to complete NLST listing: ${nlstTransferResponse.message}',
        );
      }

      // Parse NLST listing (simple list of filenames)
      try {
        final nlstListing = utf8.decode(nlstRawData);
        debugPrint("FTP: NLST listing:\n$nlstListing");

        // Convert simple names to FtpFileInfo objects
        final fileNames = nlstListing
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

        debugPrint("FTP: NLST returned ${fileNames.length} items");

        // Create a list of FtpFileInfo objects from simple names
        // We can't determine if they're files or directories from NLST alone
        // So we'll make an educated guess based on extension
        final List<FtpFileInfo> result = [];
        for (final name in fileNames) {
          // Skip . and ..
          if (name == '.' || name == '..') continue;

          final fullPath = path?.endsWith('/') ?? false
              ? '$path$name'
              : '${path ?? _currentDirectory}/$name';

          // Guess if it's a directory (no extension) or a file
          final hasExtension = name.contains('.');
          final isDir = !hasExtension;

          result.add(
            FtpFileInfo(
              name: name,
              path: fullPath,
              size: 0, // Size unknown
              isDirectory: isDir,
              lastModified: null, // Date unknown
              rawListing: name,
            ),
          );

          debugPrint("FTP: Added ${isDir ? 'directory' : 'file'}: $name");
        }

        return result;
      } catch (e) {
        debugPrint("FTP: Error parsing NLST listing: $e");
      }
    }

    // Parse with the regular method
    final result = FtpFileInfo.parseDirectoryListing(
      listing,
      _currentDirectory ?? '/',
    );

    // Log the results
    debugPrint("FTP: Parsed directory listing into ${result.length} items");
    for (var item in result) {
      debugPrint(
        "FTP: - ${item.isDirectory ? 'Directory' : 'File'}: ${item.name}",
      );
    }

    return result;
  }

  /// Changes the current working directory
  Future<bool> changeDirectory(String path) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    await _sendCommand(FtpCommands.cwd(path));
    final response = await _waitForResponse();

    if (response.code != 250) {
      return false;
    }

    await _updateCurrentDirectory();
    return true;
  }

  /// Creates a new directory
  Future<bool> createDirectory(String dirName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    await _sendCommand(FtpCommands.mkd(dirName));
    final response = await _waitForResponse();

    return response.code == 257;
  }

  /// Deletes a directory
  Future<bool> deleteDirectory(String dirName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    await _sendCommand(FtpCommands.rmd(dirName));
    final response = await _waitForResponse();

    return response.code == 250;
  }

  /// Deletes a file
  Future<bool> deleteFile(String fileName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    await _sendCommand(FtpCommands.dele(fileName));
    final response = await _waitForResponse();

    return response.code == 250;
  }

  /// Renames a file or directory
  Future<bool> rename(String oldName, String newName) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    // Send RNFR command
    await _sendCommand(FtpCommands.rnfr(oldName));
    final rnfrResponse = await _waitForResponse();

    if (rnfrResponse.code != 350) {
      return false;
    }

    // Send RNTO command
    await _sendCommand(FtpCommands.rnto(newName));
    final rntoResponse = await _waitForResponse();

    return rntoResponse.code == 250;
  }

  /// Downloads a file from the server
  Future<Uint8List?> downloadFile(String remotePath) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    // Prepare data connection
    await _setupDataConnection();

    // Send RETR command
    await _sendCommand(FtpCommands.retr(remotePath));
    final retrResponse = await _waitForResponse();

    if (retrResponse.code != 150 && retrResponse.code != 125) {
      throw Exception('Failed to download file: ${retrResponse.message}');
    }

    // Read file data
    final List<int> fileData = [];
    await for (final data in _dataSocket!) {
      fileData.addAll(data);
    }

    // Close data connection
    await _closeDataConnection();

    // Wait for transfer complete message
    final transferResponse = await _waitForResponse();
    if (transferResponse.code != 226) {
      throw Exception(
        'Failed to complete file download: ${transferResponse.message}',
      );
    }

    return Uint8List.fromList(fileData);
  }

  /// Downloads a file from the server with progress tracking
  Future<Uint8List?> downloadFileWithProgress(
    String remotePath,
    void Function(int bytesReceived) onProgress,
  ) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    // Prepare data connection
    await _setupDataConnection();

    // Send RETR command
    await _sendCommand(FtpCommands.retr(remotePath));
    final retrResponse = await _waitForResponse();

    if (retrResponse.code != 150 && retrResponse.code != 125) {
      throw Exception('Failed to download file: ${retrResponse.message}');
    }

    // Read file data with progress updates
    final List<int> fileData = [];
    int totalBytesReceived = 0;

    await for (final data in _dataSocket!) {
      fileData.addAll(data);
      totalBytesReceived += data.length;

      // Notify progress
      onProgress(totalBytesReceived);
    }

    // Close data connection
    await _closeDataConnection();

    // Wait for transfer complete message
    final transferResponse = await _waitForResponse();
    if (transferResponse.code != 226) {
      throw Exception(
        'Failed to complete file download: ${transferResponse.message}',
      );
    }

    return Uint8List.fromList(fileData);
  }

  /// Uploads a file to the server
  Future<bool> uploadFile(String localPath, String remotePath) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Local file does not exist: $localPath');
    }

    // Prepare data connection
    await _setupDataConnection();

    // Send STOR command
    await _sendCommand(FtpCommands.stor(remotePath));
    final storResponse = await _waitForResponse();

    if (storResponse.code != 150 && storResponse.code != 125) {
      throw Exception('Failed to upload file: ${storResponse.message}');
    }

    // Read file and send to data connection
    final fileBytes = await file.readAsBytes();
    _dataSocket!.add(fileBytes);
    await _dataSocket!.close();

    // Wait for transfer complete message
    final transferResponse = await _waitForResponse();
    if (transferResponse.code != 226 && transferResponse.code != 250) {
      throw Exception(
        'Failed to complete file upload: ${transferResponse.message}',
      );
    }

    return true;
  }

  /// Uploads a file to the server with progress tracking
  Future<bool> uploadFileWithProgress(
    String localPath,
    String remotePath,
    void Function(int bytesSent) onProgress,
  ) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Local file does not exist: $localPath');
    }

    // Prepare data connection
    await _setupDataConnection();

    // Send STOR command
    await _sendCommand(FtpCommands.stor(remotePath));
    final storResponse = await _waitForResponse();

    if (storResponse.code != 150 && storResponse.code != 125) {
      throw Exception('Failed to upload file: ${storResponse.message}');
    }

    // Read file in chunks and send to data connection with progress updates
    final fileStream = file.openRead();
    int totalBytesSent = 0;

    await for (final chunk in fileStream) {
      _dataSocket!.add(chunk);
      totalBytesSent += chunk.length;

      // Notify progress
      onProgress(totalBytesSent);
    }

    await _dataSocket!.close();

    // Wait for transfer complete message
    final transferResponse = await _waitForResponse();
    if (transferResponse.code != 226 && transferResponse.code != 250) {
      throw Exception(
        'Failed to complete file upload: ${transferResponse.message}',
      );
    }

    return true;
  }

  /// Uploads data directly to the server
  Future<bool> uploadData(Uint8List data, String remotePath) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    // Prepare data connection
    await _setupDataConnection();

    // Send STOR command
    await _sendCommand(FtpCommands.stor(remotePath));
    final storResponse = await _waitForResponse();

    if (storResponse.code != 150 && storResponse.code != 125) {
      throw Exception(
        'Failed to initiate data upload: ${storResponse.message}',
      );
    }

    // Send data
    _dataSocket!.add(data);
    await _dataSocket!.flush();

    // Close data connection
    await _closeDataConnection();

    // Wait for transfer complete message
    final transferResponse = await _waitForResponse();
    return transferResponse.code == 226;
  }

  /// Changes to the parent directory
  Future<bool> goToParentDirectory() async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    await _sendCommand(FtpCommands.cdup());
    final response = await _waitForResponse();

    if (response.code != 250) {
      return false;
    }

    await _updateCurrentDirectory();
    return true;
  }

  /// Sets passive mode for data connections
  Future<bool> setPassiveMode(bool usePassive) async {
    if (!_isConnected) {
      throw Exception('Not connected to FTP server');
    }

    _usePassiveMode = usePassive;
    debugPrint('FTP: Set passive mode to $_usePassiveMode');

    // No need to send any command to server, we'll use this setting
    // when establishing data connections
    return true;
  }

  /// Toggles between passive and active mode
  /// Can be helpful when one mode doesn't work with a specific server
  Future<bool> togglePassiveMode() async {
    return setPassiveMode(!_usePassiveMode);
  }

  /// Updates the current directory by sending PWD command
  Future<void> _updateCurrentDirectory() async {
    await _sendCommand(FtpCommands.pwd());
    final response = await _waitForResponse();

    if (response.code == 257) {
      // Extract directory from response (format: 257 "/directory" is current directory)
      final match = RegExp(r'"(.*?)"').firstMatch(response.message);
      if (match != null) {
        _currentDirectory = match.group(1);
      }
    }
  }

  /// Sets up data connection for file transfers
  Future<void> _setupDataConnection() async {
    if (_usePassiveMode) {
      await _setupPassiveDataConnection();
    } else {
      await _setupActiveDataConnection();
    }
  }

  /// Sets up a passive data connection
  Future<void> _setupPassiveDataConnection() async {
    // Close any existing data connection
    await _closeDataConnection();

    // Request passive mode
    await _sendCommand(FtpCommands.pasv());
    final response = await _waitForResponse();

    if (response.code != 227) {
      throw Exception('Failed to enter passive mode: ${response.message}');
    }

    // Parse the passive mode response to extract IP and port
    final match = RegExp(
      r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)',
    ).firstMatch(response.message);
    if (match == null) {
      throw Exception('Invalid passive mode response: ${response.message}');
    }

    // Extract IP address and port from response
    final ip =
        '${match.group(1)}.${match.group(2)}.${match.group(3)}.${match.group(4)}';
    final port =
        (int.parse(match.group(5)!) * 256) + int.parse(match.group(6)!);

    debugPrint('FTP: Connecting to passive mode address $ip:$port');

    // Connect to the data port
    try {
      _dataSocket = await Socket.connect(ip, port);
    } catch (e) {
      debugPrint('FTP: Error connecting to passive data port: $e');
      throw Exception('Failed to connect to passive mode port: $e');
    }
  }

  /// Sets up an active data connection
  Future<void> _setupActiveDataConnection() async {
    // Close any existing data connection
    await _closeDataConnection();

    // Create a server socket on a random port
    final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = serverSocket.port;

    // Get local IP
    String localIp = '127.0.0.1'; // Fallback
    try {
      // Try to get local IP address from control socket
      final controlSocketInfo = _controlSocket?.address.address ?? '';
      if (controlSocketInfo.isNotEmpty) {
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              localIp = addr.address;
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('FTP: Error getting local IP: $e, using 127.0.0.1');
    }

    // Convert IP and port to PORT command format
    final ipParts = localIp.split('.');
    final p1 = port ~/ 256;
    final p2 = port % 256;
    final portCmd = '${ipParts.join(',')},$p1,$p2';

    // Send PORT command
    await _sendCommand(FtpCommands.port(portCmd));
    final portResponse = await _waitForResponse();

    if (portResponse.code != 200) {
      await serverSocket.close();
      throw Exception('Failed to set up active mode: ${portResponse.message}');
    }

    // Listen for incoming connection from server
    serverSocket.listen((socket) {
      _dataSocket = socket;
      serverSocket.close();
    });

    // Set a timeout for the server connection
    Future.delayed(const Duration(seconds: 10), () {
      if (_dataSocket == null) {
        serverSocket.close();
        throw Exception('Timeout waiting for server to connect in active mode');
      }
    });
  }

  /// Closes the data connection
  Future<void> _closeDataConnection() async {
    if (_dataSocket != null) {
      await _dataSocket!.close();
      _dataSocket = null;
    }

    if (_passiveServer != null) {
      await _passiveServer!.close();
      _passiveServer = null;
    }
  }

  /// Sends a command to the FTP server
  Future<void> _sendCommand(String command) async {
    if (_controlSocket == null) {
      throw Exception('Not connected to FTP server');
    }

    debugPrint('> $command');
    _controlSocket!.write('$command\r\n');
    await _controlSocket!.flush();
  }

  /// Waits for a response from the FTP server
  Future<FtpResponse> _waitForResponse() {
    _commandCompleter = Completer<FtpResponse>();
    return _commandCompleter!.future;
  }

  /// Handles incoming data on the control connection
  void _handleControlResponse(List<int> data) {
    final response = utf8.decode(data);
    debugPrint('< $response');

    final lines = response
        .split('\r\n')
        .where((line) => line.isNotEmpty)
        .toList();

    for (final line in lines) {
      final ftpResponse = FtpResponse.parse(line);
      _responseController.add(ftpResponse);

      // Complete the current command if waiting
      if (_commandCompleter != null && !_commandCompleter!.isCompleted) {
        _commandCompleter!.complete(ftpResponse);
      }
    }
  }

  /// Handles errors on the control connection
  void _handleControlError(Object error) {
    _handleError('Control connection error: $error');

    // Complete the current command with an error
    if (_commandCompleter != null && !_commandCompleter!.isCompleted) {
      _commandCompleter!.completeError(error);
    }
  }

  /// Handles the control connection being closed
  void _handleControlDone() {
    _isConnected = false;
    debugPrint('FTP control connection closed');

    // Complete the current command with an error if necessary
    if (_commandCompleter != null && !_commandCompleter!.isCompleted) {
      _commandCompleter!.completeError(Exception('Connection closed'));
    }
  }

  /// Handles errors
  void _handleError(String message) {
    debugPrint(message);
    _isConnected = false;
  }
}
