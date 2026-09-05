/// Removes model reasoning before displaying text or looking for tool calls.
/// Accepts accumulated streaming text, including split and unclosed tags.
String stripAssistantReasoning(String text) {
  var result = text.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  // Some templates supply the opening tag as part of the prompt.
  final closing = RegExp(r'</think>', caseSensitive: false).firstMatch(result);
  if (closing != null) result = result.substring(closing.end);
  result = result.replaceAll(
    RegExp(r'<think>[\s\S]*$', caseSensitive: false),
    '',
  );
  final lastLt = result.lastIndexOf('<');
  if (lastLt >= 0) {
    final tail = result.substring(lastLt).toLowerCase();
    if ('<think>'.startsWith(tail) || '</think>'.startsWith(tail)) {
      result = result.substring(0, lastLt);
    }
  }
  return result.trim();
}

/// Extracts reasoning for a separate, collapsed UI section, including streams.
String extractAssistantReasoning(String text) {
  final blocks = RegExp(
    r'<think>([\s\S]*?)(?:</think>|$)',
    caseSensitive: false,
  ).allMatches(text).map((match) => match.group(1)!.trim()).toList();
  if (blocks.isEmpty) {
    final closing = RegExp(r'</think>', caseSensitive: false).firstMatch(text);
    if (closing != null) return text.substring(0, closing.start).trim();
  }
  return blocks
      .map((block) {
        final lastLt = block.lastIndexOf('<');
        if (lastLt >= 0 && '</think>'.startsWith(block.substring(lastLt))) {
          return block.substring(0, lastLt).trim();
        }
        return block;
      })
      .where((block) => block.isNotEmpty)
      .join('\n\n');
}
