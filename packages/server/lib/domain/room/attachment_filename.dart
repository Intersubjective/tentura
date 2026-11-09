/// User-visible attachment filename for DB / UI (preserves Unicode).
String attachmentDisplayName(String raw) {
  var s = _attachmentBaseName(raw);
  if (s.isEmpty || s == '.' || s == '..') {
    return 'file';
  }
  s = s.replaceAll(RegExp(r'[\x00-\x1F\x7F"\\]'), '');
  if (s.isEmpty) {
    return 'file';
  }
  if (s.length > 200) {
    s = s.substring(0, 200);
  }
  return s;
}

/// ASCII-safe single-segment filename for Content-Disposition filename=.
String sanitizedAttachmentBaseName(String raw) {
  var s = _attachmentBaseName(raw);
  if (s.isEmpty) {
    return 'file';
  }
  if (s.length > 200) {
    s = s.substring(0, 200);
  }
  return s.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]+'), '_');
}

String _attachmentBaseName(String raw) =>
    raw.split(RegExp(r'[/\\]')).last.trim();
