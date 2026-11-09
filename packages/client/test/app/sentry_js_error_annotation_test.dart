import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/app/sentry/js_error_details.dart';

class _FakeJsError {
  const _FakeJsError();
}

const _jsError = _FakeJsError();

JsErrorDetails? _read(Object? throwable) => identical(throwable, _jsError)
    ? const JsErrorDetails(
        name: 'OperationError',
        message: 'The operation failed for an operation-specific reason',
        stack: 'OperationError\n    at decrypt (crypto)',
      )
    : null;

SentryEvent _eventFor(Object throwable) => SentryEvent(
  throwable: throwable,
  exceptions: [
    SentryException(type: 'minified:Class1109', value: 'Instance of minified')
      ..throwable = throwable,
  ],
);

void main() {
  test('a JS error reads as its browser name and message, stack kept', () {
    final event = _eventFor(_jsError);

    annotateJsErrorEvent(event, _read);

    final exception = event.exceptions!.single;
    expect(exception.type, 'OperationError');
    expect(
      exception.value,
      'The operation failed for an operation-specific reason',
    );
    final extra = event.contexts['js_error'] as Map;
    expect(extra['dart_type'], 'minified:Class1109');
    expect(extra['stack'], contains('at decrypt'));
    expect(event.tags!['js_error_name'], 'OperationError');
  });

  test('a Dart throwable is left unchanged', () {
    final event = _eventFor(StateError('boom'));

    annotateJsErrorEvent(event, _read);

    expect(event.exceptions!.single.type, 'minified:Class1109');
    expect(event.contexts['js_error'], isNull);
    expect(event.tags, isNull);
  });

  test('a long JS stack is truncated', () {
    final event = _eventFor(_jsError);

    annotateJsErrorEvent(
      event,
      (_) => JsErrorDetails(
        name: 'TypeError',
        message: '',
        stack: 'x' * (kJsErrorStackMaxChars + 100),
      ),
    );

    final extra = event.contexts['js_error'] as Map;
    expect((extra['stack'] as String).length, kJsErrorStackMaxChars);
    // An empty JS message keeps the original value.
    expect(event.exceptions!.single.value, 'Instance of minified');
  });

  test('off the web nothing is read as a JS error', () {
    expect(readJsErrorDetails(StateError('boom')), isNull);
  });
}
