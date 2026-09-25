/// Truncates [s] to at most [maxLength] characters, using U+2026 when shortened.
String ellipsize(String s, int maxLength) {
  if (maxLength < 1) return '';
  if (s.length <= maxLength) return s;
  return '${s.substring(0, maxLength - 1)}…';
}
