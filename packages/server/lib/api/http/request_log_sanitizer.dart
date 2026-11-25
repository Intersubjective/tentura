const _redactedValue = '<redacted>';

final _sensitiveQueryParameter = RegExp(
  r'([?&](?:_qa_token|objectKey)=)[^&\s]*',
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
