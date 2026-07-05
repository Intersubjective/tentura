import 'package:tentura_server/utils/sanitized_attachment_name.dart';

/// HTTP [Content-Disposition] for attachment downloads with UTF-8 filename.
///
/// [filename*=UTF-8''] must be percent-encoded: raw Unicode in header values
/// throws [FormatException] under dart:io / shelf_io.
Map<String, String> attachmentDownloadContentDisposition(String fileName) {
  final ascii = sanitizedAttachmentBaseName(fileName);
  final encoded = _rfc5987Encode(fileName);
  return {
    'Content-Disposition':
        'attachment; filename="$ascii"; filename*=UTF-8\'\'$encoded',
  };
}

/// Percent-encodes for RFC 5987 filename*; also encodes ! * ' ( ) which
/// [Uri.encodeComponent] leaves unescaped (non-canonical but browsers accept).
String _rfc5987Encode(String fileName) {
  var encoded = Uri.encodeComponent(fileName);
  const extra = {
    '!': '%21',
    '*': '%2A',
    "'": '%27',
    '(': '%28',
    ')': '%29',
  };
  for (final entry in extra.entries) {
    encoded = encoded.replaceAll(entry.key, entry.value);
  }
  return encoded;
}
