/// The type of action the agent is requesting approval to perform.
enum ApprovalActionType {
  /// Execute a shell command.
  execute,

  /// Create a new file (write_file on a path that does not exist yet).
  createFile,

  /// Modify an existing file (write_file on an existing path).
  modifyFile,

  /// Permanently delete a file or directory.
  deleteFile,

  /// Generic / unknown action.
  generic,
}

/// A request from the AI agent that requires user approval before executing.
class AiApprovalRequest {
  final String id;
  final String title;
  final String description;
  final String confirmLabel;
  final bool isDangerous;

  /// Semantic type used by the UI to pick the right icon and colour scheme.
  final ApprovalActionType actionType;

  const AiApprovalRequest({
    required this.id,
    required this.title,
    required this.description,
    this.confirmLabel = 'Confirm',
    this.isDangerous = false,
    this.actionType = ApprovalActionType.generic,
  });
}
