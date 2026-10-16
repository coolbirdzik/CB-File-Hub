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

/// A short closing promise to inspect data is an intermediate step, not an
/// answer. Request another model round; never infer or execute a tool from it.
bool endsWithPendingInspection(String text) {
  final visible = stripAssistantReasoning(text);
  final lines = visible.split('\n').where((line) => line.trim().isNotEmpty);
  if (lines.isEmpty) return false;
  final last = lines.last.trim().replaceAll(RegExp(r'[*_`]'), '').toLowerCase();
  if (last.length > 500 || last.endsWith('?')) return false;
  if (RegExp(r'[.!]\s+\S').hasMatch(last)) return false;
  // Conditional offers and requests for user input are valid stopping points.
  if (RegExp(
    r'\b(?:if you|once you|after you|when you|later|tomorrow)\b|'
    r'nếu bạn|khi bạn|sau khi bạn|nếu anh|nếu chị|ngày mai',
  ).hasMatch(last)) {
    return false;
  }
  return RegExp(
    r'^(?:(?:để|to)\s+[^.!?\n]{1,180}[,:]\s*)?'
    r'(?:(?:tôi|mình|em|chúng ta)\s+sẽ\s+'
    r'(?:kiểm tra|xem|tìm|đọc|quét|phân tích)|'
    r'(?:i(?: will|[\x27’]ll| am going to)|let me)\s+'
    r'(?:check|inspect|search|read|scan|look|analyze|analyse)\b)',
  ).hasMatch(last);
}
