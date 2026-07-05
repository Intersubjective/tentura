/// User-visible attachment filename for DB / UI (preserves Unicode).
String attachmentDisplayName(String raw) {
  var s = raw.split(RegExp(r'[/\\]')).last.trim();
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
