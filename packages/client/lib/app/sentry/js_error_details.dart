import 'package:sentry_flutter/sentry_flutter.dart';

export 'js_error_details_stub.dart'
    if (dart.library.js_interop) 'js_error_details_web.dart';

/// What a thrown JavaScript value (a `DOMException`, a `TypeError`, …) says
/// about itself. On web a JS error caught in Dart is an opaque wrapper: its
/// Dart type prints as `minified:ClassNNNN` and the browser's message is lost
/// (#1041, #1216). These fields are read straight from the JS object.
class JsErrorDetails {
  const JsErrorDetails({required this.name, required this.message, this.stack});

  final String name;
  final String message;
  final String? stack;
}

/// Longest JS stack kept in the `js_error` context; Sentry truncates large payloads.
const kJsErrorStackMaxChars = 4000;

/// Rewrites every exception of [event] whose throwable is a JS error so it
/// reads `OperationError: <browser message>` instead of a minified Dart type,
/// and keeps the JS stack (it names the browser API that threw) in
/// the `js_error` context. Non-JS throwables are left as they are.
void annotateJsErrorEvent(
  SentryEvent event,
  JsErrorDetails? Function(Object? throwable) read,
) {
  final exceptions = event.exceptions;
  if (exceptions == null || exceptions.isEmpty) {
    return;
  }
  for (final exception in exceptions) {
    final details = read(exception.throwable ?? event.throwable);
    if (details == null) {
      continue;
    }
    final originalType = exception.type;
    exception
      ..type = details.name
      ..value = details.message.isEmpty ? exception.value : details.message;
    final stack = details.stack;
    event.contexts['js_error'] = <String, Object>{
      'name': details.name,
      'message': details.message,
      'dart_type': ?originalType,
      if (stack != null && stack.isNotEmpty)
        'stack': stack.length > kJsErrorStackMaxChars
            ? stack.substring(0, kJsErrorStackMaxChars)
            : stack,
    };
    (event.tags ??= {})['js_error_name'] = details.name;
  }
}
