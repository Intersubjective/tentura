const kOpaqueScriptErrorLiterals = {'script error.', 'script error'};

bool isOpaqueScriptErrorLiteral(String? text) {
  if (text == null) {
    return false;
  }
  final normalized = text.trim().toLowerCase();
  return kOpaqueScriptErrorLiterals.contains(normalized);
}

/// Drop iff every non-empty candidate is an opaque literal and at least one
/// candidate exists. Mixed opaque + real payloads must not drop.
bool isOpaqueBrowserScriptErrorEvent({
  String? message,
  String? messageFormatted,
  String? messageObjectMessage,
  Iterable<String?> exceptionValues = const [],
}) {
  final candidates = <String>[];

  void addCandidate(String? text) {
    if (text != null && text.trim().isNotEmpty) {
      candidates.add(text);
    }
  }

  addCandidate(message);
  addCandidate(messageFormatted);
  addCandidate(messageObjectMessage);
  for (final value in exceptionValues) {
    addCandidate(value);
  }

  if (candidates.isEmpty) {
    return false;
  }
  return candidates.every(isOpaqueScriptErrorLiteral);
}
