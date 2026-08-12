/// Canonical context normalization for capability witness windows and
/// forward candidate queries. Must stay in parity with
/// `public.cap_normalize_context(text)` (see architecture §3.5).
String capNormalizeContext(String? context) {
  if (context == null) {
    return '';
  }
  final trimmed = _btrimAsciiSpaces(context);
  if (trimmed.length < 3 || trimmed.length > 32) {
    return '';
  }
  return trimmed;
}

/// PostgreSQL `btrim(text)` with no character-set argument: removes only
/// leading/trailing ASCII space (U+0020), not tabs or other whitespace.
String _btrimAsciiSpaces(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && value.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && value.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return value.substring(start, end);
}
