import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/services/network_browsing/optimized_smb_service.dart';
import '../components/streaming/stream_speed_indicator.dart';
import '../utils/route.dart';

/// Dialog to show detailed streaming performance information
class StreamingPerformanceDialog extends StatefulWidget {
  final OptimizedSMBService smbService;
  final String? currentFilePath;
  final Stream<List<int>>? currentStream;

  const StreamingPerformanceDialog({
    Key? key,
    required this.smbService,
    this.currentFilePath,
    this.currentStream,
  }) : super(key: key);

  @override
  State<StreamingPerformanceDialog> createState() =>
      _StreamingPerformanceDialogState();
}

class _StreamingPerformanceDialogState
    extends State<StreamingPerformanceDialog> {
  Map<String, dynamic> _performanceStats = {};
  Map<String, dynamic>? _benchmarkResults;
  bool _isBenchmarking = false;

  @override
  void initState() {
    super.initState();
    _loadPerformanceStats();
  }

  Future<void> _loadPerformanceStats() async {
    try {
      final stats = widget.smbService.getPerformanceStats();
      setState(() {
        _performanceStats = stats;
      });
    } catch (e) {
      debugPrint('Error loading performance stats: $e');
    }
  }

  Future<void> _runBenchmark() async {
    if (widget.currentFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file selected for benchmarking')),
      );
      return;
    }

    setState(() {
      _isBenchmarking = true;
    });

    try {
      final results =
          await widget.smbService.benchmarkStreaming(widget.currentFilePath!);
      if (mounted) {
        setState(() {
          _benchmarkResults = results;
          _isBenchmarking = false;
        });

        if (results['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Benchmark error: ${results['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBenchmarking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Benchmark failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Streaming Performance',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => RouteUtils.safePopDialog(context),
                  icon: const Icon(PhosphorIconsLight.x),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Real-time speed indicator
            if (widget.currentStream != null) ...[
              StreamSpeedIndicator(
                stream: widget.currentStream,
                label: 'Current Stream',
              ),
              const SizedBox(height: 16),
            ],

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Connection Status
                    _buildStatusCard(),
                    const SizedBox(height: 12),

                    // Performance Metrics
                    _buildPerformanceCard(),
                    const SizedBox(height: 12),

                    // Benchmark Section
                    _buildBenchmarkCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final isConnected = _performanceStats['isConnected'] ?? false;
    final streamingMethod = _performanceStats['streamingMethod'] ?? 'Unknown';
    final optimizationLevel =
        _performanceStats['optimizationLevel'] ?? 'Unknown';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Status',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInfoRow('Streaming Method', streamingMethod),
            _buildInfoRow('Optimization Level', optimizationLevel),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCard() {
    final streaming = _performanceStats['streaming'] as Map<String, dynamic>?;
    final prefetchController =
        _performanceStats['prefetchController'] as Map<String, dynamic>?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Performance Configuration',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (streaming != null) ...[
              _buildInfoRow('Chunk Size', streaming['chunkSize'] ?? 'Unknown'),
              _buildInfoRow(
                  'Buffer Size', streaming['bufferSize'] ?? 'Unknown'),
              _buildInfoRow(
                  'Prefetch Size', streaming['prefetchSize'] ?? 'Unknown'),
              _buildInfoRow('Max Connections',
                  '${streaming['maxConnections'] ?? 'Unknown'}'),
              _buildInfoRow(
                  'Estimated Speed', streaming['estimatedSpeed'] ?? 'Unknown'),
            ],
            if (prefetchController != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow('Cache Hit Rate',
                  '${prefetchController['cacheHitRate'] ?? '0.0'}%'),
              _buildInfoRow('Buffer Usage',
                  '${prefetchController['bufferSize'] ?? 0} bytes'),
              _buildInfoRow(
                  'Buffer Count', '${prefetchController['bufferCount'] ?? 0}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Speed Test',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ElevatedButton.icon(
                  onPressed: _isBenchmarking ? null : _runBenchmark,
                  icon: _isBenchmarking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsLight.speedometer, size: 16),
                  label: Text(_isBenchmarking ? 'Testing...' : 'Run Test'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_benchmarkResults != null) ...[
              _buildBenchmarkResults(),
            ] else ...[
              const Text(
                'Click "Run Test" to measure streaming performance',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkResults() {
    final results = _benchmarkResults!;
    final error = results['error'];

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Text(
          'Error: $error',
          style: TextStyle(color: Colors.red.shade700),
        ),
      );
    }

    final speedMBps = results['speedMBps'] ?? '0.00';
    final speedKBps = results['speedKBps'] ?? '0';
    final totalBytes = results['totalBytes'] ?? 0;
    final chunkCount = results['chunkCount'] ?? 0;
    final testDuration = results['testDuration'] ?? 0;
    final fileName = results['fileName'] ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test File: $fileName',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Speed:', style: TextStyle(fontSize: 14)),
              Text(
                '$speedMBps MB/s ($speedKBps KB/s)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Data Transferred',
              '${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
          _buildInfoRow('Chunks Processed', '$chunkCount'),
          _buildInfoRow('Test Duration', '${testDuration}ms'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
