import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'js_error_details.dart';

/// Reads `name` / `message` / `stack` from a thrown JS error object.
/// Returns null for Dart throwables and for JS values that aren't errors.
JsErrorDetails? readJsErrorDetails(Object? throwable) {
  // A JS value caught in Dart is the JS-interop representation type; a Dart
  // object never is, so this runtime check is exactly "was a JS value thrown".
  // ignore: invalid_runtime_check_with_js_interop_types
  if (throwable is! JSAny || !throwable.isA<JSObject>()) {
    return null;
  }
  final object = throwable as JSObject;
  final name = _string(object, 'name');
  final message = _string(object, 'message');
  if (name == null && message == null) {
    return null;
  }
  return JsErrorDetails(
    name: name ?? 'Error',
    message: message ?? '',
    stack: _string(object, 'stack'),
  );
}

String? _string(JSObject object, String key) {
  try {
    final value = object.getProperty<JSAny?>(key.toJS);
    return value != null && value.isA<JSString>()
        ? (value as JSString).toDart
        : null;
  } on Object {
    // A throwing getter on an exotic object must not break reporting.
    return null;
  }
}
