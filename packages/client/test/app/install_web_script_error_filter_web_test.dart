@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/sentry/install_web_script_error_filter.dart';

JSObject get _global => web.window as JSObject;

void main() {
  group('installWebScriptErrorFilter (web)', () {
  late JSObject options;
  var previousCalls = 0;
  var previousReturnsNull = false;

  setUp(() {
    previousCalls = 0;
    previousReturnsNull = false;
    options = JSObject();
    options.setProperty(
      'beforeSend'.toJS,
      ((JSAny? event, JSAny? hint) {
        previousCalls++;
        return previousReturnsNull ? null : event;
      }).toJS,
    );

    final client = JSObject();
    client.setProperty('getOptions'.toJS, (() => options).toJS);

    final sentry = JSObject();
    sentry.setProperty('getClient'.toJS, (() => client).toJS);
    _global.setProperty('Sentry'.toJS, sentry);
  });

  tearDown(() {
    _global.delete('Sentry'.toJS);
    options.delete('__tenturaScriptErrorFilter'.toJS);
    options.delete('beforeSend'.toJS);
  });

  JSFunction _wrappedBeforeSend() {
    final fn = options.getProperty('beforeSend'.toJS);
    expect(fn, isNotNull);
    expect(fn!.isA<JSFunction>(), isTrue);
    return fn! as JSFunction;
  }

  JSObject makeEvent({
    String? message,
    JSObject? messageObject,
    List<String>? exceptionValues,
  }) {
    final event = JSObject();
    if (messageObject != null) {
      event.setProperty('message'.toJS, messageObject);
    } else if (message != null) {
      event.setProperty('message'.toJS, message.toJS);
    }
    if (exceptionValues != null) {
      final values = <JSObject>[];
      for (final value in exceptionValues) {
        final entry = JSObject();
        entry.setProperty('value'.toJS, value.toJS);
        values.add(entry);
      }
      final exception = JSObject();
      exception.setProperty('values'.toJS, values.toJS);
      event.setProperty('exception'.toJS, exception);
    }
    return event;
  }

  test('drops opaque exception values without calling previous', () {
    installWebScriptErrorFilter();

    final event = makeEvent(exceptionValues: ['Script error.']);
    final result = _wrappedBeforeSend().callAsFunction(options, event, null);

    expect(result, isNull);
    expect(previousCalls, 0);
  });

  test('keeps real exceptions and chains previous beforeSend', () {
    installWebScriptErrorFilter();

    final event = makeEvent(
      exceptionValues: ['Null check operator used on a null value'],
    );
    final result = _wrappedBeforeSend().callAsFunction(options, event, null);

    expect(result, same(event));
    expect(previousCalls, 1);
  });

  test('keeps prefixed script error messages and chains previous', () {
    installWebScriptErrorFilter();

    final event = makeEvent(message: 'Exception: Script error.');
    final result = _wrappedBeforeSend().callAsFunction(options, event, null);

    expect(result, same(event));
    expect(previousCalls, 1);
  });

  test('reads object message fields', () {
    installWebScriptErrorFilter();

    final messageObj = JSObject();
    messageObj.setProperty('formatted'.toJS, 'Script error.'.toJS);
    messageObj.setProperty('message'.toJS, 'Script error.'.toJS);
    final opaqueEvent = makeEvent(messageObject: messageObj);
    final opaqueResult =
        _wrappedBeforeSend().callAsFunction(options, opaqueEvent, null);
    expect(opaqueResult, isNull);
    expect(previousCalls, 0);

    final mixedMessageObj = JSObject();
    mixedMessageObj.setProperty('formatted'.toJS, 'Script error.'.toJS);
    mixedMessageObj.setProperty(
      'message'.toJS,
      'Null check operator used on a null value'.toJS,
    );
    final mixedEvent = makeEvent(messageObject: mixedMessageObj);
    final mixedResult =
        _wrappedBeforeSend().callAsFunction(options, mixedEvent, null);
    expect(mixedResult, same(mixedEvent));
    expect(previousCalls, 1);
  });

  test('keeps mixed opaque and real exception values', () {
    installWebScriptErrorFilter();

    final event = makeEvent(
      exceptionValues: [
        'Script error.',
        'Null check operator used on a null value',
      ],
    );
    final result = _wrappedBeforeSend().callAsFunction(options, event, null);

    expect(result, same(event));
    expect(previousCalls, 1);
  });

  test('is idempotent on double install', () {
    installWebScriptErrorFilter();
    final first = options.getProperty('beforeSend'.toJS);

    installWebScriptErrorFilter();
    final second = options.getProperty('beforeSend'.toJS);

    expect(second, same(first));
  });

  test('returns event when no previous callback exists', () {
    options.delete('beforeSend'.toJS);

    installWebScriptErrorFilter();

    final event = makeEvent(
      exceptionValues: ['Null check operator used on a null value'],
    );
    final result = _wrappedBeforeSend().callAsFunction(options, event, null);

    expect(result, same(event));
    expect(previousCalls, 0);
  });

  test('returns null when previous callback returns null', () {
    previousReturnsNull = true;
    installWebScriptErrorFilter();

    final event = makeEvent(
      exceptionValues: ['Null check operator used on a null value'],
    );
    final result = _wrappedBeforeSend().callAsFunction(options, event, null);

    expect(result, isNull);
    expect(previousCalls, 1);
  });
  });
}
