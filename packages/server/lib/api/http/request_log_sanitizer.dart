const _redactedValue = '<redacted>';

// Shelf logs the normalized URI, where the BOM remains percent-encoded.
// Dart drops a leading UTF-8 BOM when decoding a query parameter name.
final _sensitiveQueryParameter = RegExp(
  r'([?&](?:%EF%BB%BF)?(?:_qa_token|objectKey)=)[^&\s]*',
);

String sanitizeRequestLogMessage(String message) => message.replaceAllMapped(
  _sensitiveQueryParameter,
  (match) => '${match.group(1)}$_redactedValue',
);

void sanitizedRequestLogger(
  String message, {
  required bool isError,
}) {
  final sanitized = sanitizeRequestLogMessage(message);
  if (isError) {
    print('[ERROR] $sanitized');
  } else {
    print(sanitized);
  }
}
