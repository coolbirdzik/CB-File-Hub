import 'disk_tree_node.dart';

enum CleanerItemDecision { clean, review, keep }

class CleanerItemAnalysis {
  final CleanerItemDecision decision;
  final String reason;
  final bool selectForCleanup;

  const CleanerItemAnalysis({
    required this.decision,
    required this.reason,
    this.selectForCleanup = false,
  });
}

class CleanerReviewedItem {
  final DiskTreeNode node;
  final CleanerItemAnalysis analysis;

  const CleanerReviewedItem({required this.node, required this.analysis});
}

class CleanerItemInteractionResult {
  final DiskTreeNode? node;
  final String? scanId;
  final String? error;

  const CleanerItemInteractionResult({this.node, this.scanId, this.error});
}
