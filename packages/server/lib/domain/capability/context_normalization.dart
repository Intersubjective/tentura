/// Canonical context normalization for capability witness windows and
/// forward candidate queries. Must stay in parity with
/// `public.cap_normalize_context(text)` (see architecture §3.5).
String capNormalizeContext(String? context) {
  if (context == null) {
    return '';
  }
  final trimmed = context.trim();
  if (trimmed.length < 3 || trimmed.length > 32) {
    return '';
  }
  return trimmed;
}
