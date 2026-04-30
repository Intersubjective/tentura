/// Safe single-segment filename for storage paths and Content-Disposition.
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
