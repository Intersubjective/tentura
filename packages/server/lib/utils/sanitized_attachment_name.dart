/// ASCII-safe single-segment filename for Content-Disposition filename=.
String sanitizedAttachmentBaseName(String raw) {
  var s = raw.split(RegExp(r'[/\\]')).last.trim();
  if (s.isEmpty) {
    return 'file';
  }
  if (s.length > 200) {
    s = s.substring(0, 200);
  }
  return s.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]+'), '_');
}
