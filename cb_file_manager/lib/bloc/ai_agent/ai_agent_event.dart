import 'package:equatable/equatable.dart';

import '../../services/ai/file_context_builder.dart';

/// Base class for all AI agent events.
abstract class AiAgentEvent extends Equatable {
  const AiAgentEvent();

  @override
  List<Object?> get props => [];
}

/// Send a chat message to the AI agent.
class SendMessage extends AiAgentEvent {
  final String message;

  /// List of file paths that were dropped/dragged into the chat.
  final List<String> referencedFiles;

  const SendMessage(this.message, {this.referencedFiles = const []});

  @override
  List<Object?> get props => [message, referencedFiles];
}

/// Stop the currently active AI generation or tool loop.
class StopGeneration extends AiAgentEvent {
  const StopGeneration();
}

/// Clear the chat history.
class ClearChat extends AiAgentEvent {
  const ClearChat();
}

/// Replace an old user message and rerun the conversation from that point.
class EditMessage extends AiAgentEvent {
  final String messageId;
  final String content;

  const EditMessage({
    required this.messageId,
    required this.content,
  });

  @override
  List<Object?> get props => [messageId, content];
}

/// Change the file search scope.
class ChangeSearchScope extends AiAgentEvent {
  final SearchScope scope;

  const ChangeSearchScope(this.scope);

  @override
  List<Object?> get props => [scope];
}

/// Quick AI search from the smart search bar.
class QuickSearch extends AiAgentEvent {
  final String query;

  const QuickSearch(this.query);

  @override
  List<Object?> get props => [query];
}

/// Update the current directory path for context building.
class UpdateCurrentPath extends AiAgentEvent {
  final String path;

  const UpdateCurrentPath(this.path);

  @override
  List<Object?> get props => [path];
}

/// Retry the last failed message.
class RetryLastMessage extends AiAgentEvent {
  const RetryLastMessage();
}

/// React to provider configuration changes.
class ProviderChanged extends AiAgentEvent {
  const ProviderChanged();
}

/// Load or refresh the grouped provider model list for chat model selection.
class RefreshProviderModels extends AiAgentEvent {
  const RefreshProviderModels();
}

/// Change the provider/model selection used for new chat turns.
class SelectChatModel extends AiAgentEvent {
  final String providerId;
  final String modelName;

  const SelectChatModel({
    required this.providerId,
    required this.modelName,
  });

  @override
  List<Object?> get props => [providerId, modelName];
}

/// Initialize the BLoC (check provider availability).
class InitializeAiAgent extends AiAgentEvent {
  final bool startFreshConversation;
  final String workspacePath;

  const InitializeAiAgent({
    this.startFreshConversation = false,
    this.workspacePath = '',
  });

  @override
  List<Object?> get props => [startFreshConversation, workspacePath];
}

/// User approved a pending AI action.
class ApproveAction extends AiAgentEvent {
  final String approvalId;
  const ApproveAction(this.approvalId);

  @override
  List<Object?> get props => [approvalId];
}

/// User rejected a pending AI action.
class RejectAction extends AiAgentEvent {
  final String approvalId;
  const RejectAction(this.approvalId);

  @override
  List<Object?> get props => [approvalId];
}

/// Start a new empty conversation (the current one is preserved in history).
class NewConversation extends AiAgentEvent {
  const NewConversation();
}

/// Switch to an existing conversation by [id].
class SwitchConversation extends AiAgentEvent {
  final String id;
  const SwitchConversation(this.id);

  @override
  List<Object?> get props => [id];
}

/// Delete a conversation by [id].
class DeleteConversation extends AiAgentEvent {
  final String id;
  const DeleteConversation(this.id);

  @override
  List<Object?> get props => [id];
}

/// Reload the conversations summary list from storage (e.g. when sidebar opens).
class RefreshConversations extends AiAgentEvent {
  const RefreshConversations();
}

/// Clear the current `state.error` banner.
class ClearError extends AiAgentEvent {
  const ClearError();
}
