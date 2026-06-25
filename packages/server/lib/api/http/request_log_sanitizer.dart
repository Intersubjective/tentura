const _redactedQaToken = '<redacted>';

final _qaTokenPattern = RegExp(r'([?&]_qa_token=)[^&\s]*');

String sanitizeRequestLogMessage(String message) => message.replaceAllMapped(
  _qaTokenPattern,
  (match) => '${match.group(1)}$_redactedQaToken',
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
