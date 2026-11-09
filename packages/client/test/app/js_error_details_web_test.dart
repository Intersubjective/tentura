@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/sentry/js_error_details.dart';

void main() {
  test('a DOMException caught in Dart reads as its name and message', () {
    Object? caught;
    try {
      web.document.querySelector('<<not a selector>>');
    } on Object catch (e) {
      caught = e;
    }

    final details = readJsErrorDetails(caught);

    expect(details, isNotNull);
    expect(details!.name, 'SyntaxError');
    expect(details.message, isNotEmpty);
  });

  test('a thrown JS TypeError keeps its stack', () {
    Object? caught;
    try {
      (web.window as JSObject).callMethod<JSAny?>('eval'.toJS, 'null.x'.toJS);
    } on Object catch (e) {
      caught = e;
    }

    final details = readJsErrorDetails(caught);

    expect(details?.name, 'TypeError');
    expect(details?.stack, isNotNull);
  });

  test('Dart throwables and plain values are not JS errors', () {
    expect(readJsErrorDetails(StateError('boom')), isNull);
    expect(readJsErrorDetails('text'), isNull);
    expect(readJsErrorDetails(null), isNull);
  });
}
