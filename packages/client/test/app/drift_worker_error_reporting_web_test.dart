@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqlite3/common.dart';

import 'package:tentura/app/sentry/install_web_script_error_filter.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/app/sentry/sentry_init.dart';

const _bareError = 'Uncaught ';
const _typeError = 'Uncaught TypeError: Cannot read properties of null';
const _sqliteError = 'Uncaught SqliteException(1): SQL logic error';
const _mainScriptPath = '/app-assets/7.63.6-2217fd7f3feb/main.dart.js';
const _rootWorkerPath = '/assets/packages/drift_worker.js';
const _versionedWorkerPath =
    '/app-assets/7.63.6-2217fd7f3feb/assets/packages/drift_worker.js';
const _globalOnError = 'auto.browser.global_handlers.onerror';

JSObject _browserError({
  required String path,
  required String mechanism,
  String value = _bareError,
}) =>
    {
          'exception': {
            'values': [
              {
                'type': 'Error',
                'value': value,
                'mechanism': {'type': mechanism, 'handled': false},
                'stacktrace': {
                  'frames': [
                    {'abs_path': path, 'in_app': true},
                  ],
                },
              },
            ],
          },
        }.jsify()!
        as JSObject;

SentryEvent _dartBrowserError(String path, String value) => SentryEvent(
  exceptions: [
    SentryException(
      type: 'Error',
      value: value,
      mechanism: Mechanism(type: 'onerror', handled: false),
      stackTrace: SentryStackTrace(
        frames: [SentryStackFrame(absPath: path, inApp: true)],
      ),
    ),
  ],
);

void main() {
  late JSObject options;
  late JSFunction beforeSend;

  setUp(() {
    final sentryKey = 'Sentry'.toJS;
    final originalSentry = globalContext.getProperty<JSAny?>(sentryKey);
    addTearDown(() {
      if (originalSentry == null) {
        globalContext.delete(sentryKey);
      } else {
        globalContext.setProperty(sentryKey, originalSentry);
      }
    });

    options = JSObject()
      ..setProperty(
        'beforeSend'.toJS,
        ((JSAny? event, JSAny? hint) => event).toJS,
      );
    final client = JSObject()
      ..setProperty('getOptions'.toJS, (() => options).toJS);
    final sentry = JSObject()
      ..setProperty('getClient'.toJS, (() => client).toJS);
    globalContext.setProperty(sentryKey, sentry);

    installWebScriptErrorFilter();
    beforeSend = options.getProperty<JSFunction>('beforeSend'.toJS);
  });

  JSAny? report(JSObject event) =>
      beforeSend.callAsFunction(options, event, null);

  void expectUnchangedBrowserReport(JSObject event) {
    final original = event.dartify();
    final reported = report(event);
    expect(reported, same(event));
    expect(reported.dartify(), original);
  }

  void expectWorkerNamed(JSAny? result) {
    expect(result, isNotNull, reason: 'keep the worker error reportable');
    final event = result.dartify()! as Map<Object?, Object?>;
    final exception = event['exception'] as Map<Object?, Object?>?;
    final values = exception?['values'] as List<Object?>?;
    final exceptionValue = (values?.single as Map<Object?, Object?>?)?['value'];
    final message = event['message'];
    final messageText = message is Map<Object?, Object?>
        ? message['formatted']
        : message;
    expect(
      [exceptionValue, messageText],
      anyElement(contains('drift_worker.js')),
      reason: 'the reported exception value or message names the worker',
    );
  }

  test('names the worker in empty browser errors from the root asset', () {
    expectWorkerNamed(
      report(_browserError(path: _rootWorkerPath, mechanism: 'onerror')),
    );
  });

  test('names the worker in empty browser errors from a versioned asset', () {
    expectWorkerNamed(
      report(_browserError(path: _versionedWorkerPath, mechanism: 'onerror')),
    );
  });

  test(
    'names the worker in browser global errors and leaves other errors intact',
    () {
      for (final (path, value) in [
        (_mainScriptPath, _bareError),
        (_versionedWorkerPath, _typeError),
        (_versionedWorkerPath, _sqliteError),
      ]) {
        expectUnchangedBrowserReport(
          _browserError(path: path, mechanism: 'onerror', value: value),
        );
      }

      expectWorkerNamed(
        report(
          _browserError(path: _versionedWorkerPath, mechanism: _globalOnError),
        ),
      );
    },
  );

  test(
    'Dart beforeSend preserves and diagnoses the worker report and keeps other errors intact',
    () async {
      final sqliteError = SqliteException(
        extendedResultCode: 1,
        message: 'SQL logic error',
      );
      expect(isBenignSentryThrowable(sqliteError), isFalse);
      final dartOptions = SentryFlutterOptions();
      configureSentryOptions(dartOptions);
      final dartBeforeSend = dartOptions.beforeSend!;
      final dartEvent = await dartBeforeSend(
        SentryEvent(throwable: sqliteError),
        Hint(),
      );
      expect(dartEvent?.throwable, same(sqliteError));

      for (final (path, value) in [
        (_mainScriptPath, _bareError),
        (_versionedWorkerPath, _typeError),
        (_versionedWorkerPath, _sqliteError),
      ]) {
        final event = _dartBrowserError(path, value);
        final original = event.toJson();
        expect(isBenignSentryEvent(event, Hint()), isFalse, reason: value);
        final reported = await dartBeforeSend(event, Hint());
        expect(reported, same(event), reason: path);
        expect(reported!.toJson(), original, reason: value);
      }

      final bareWorkerEvent = _dartBrowserError(
        _versionedWorkerPath,
        _bareError,
      );
      final originalValue = bareWorkerEvent.exceptions!.single.value;
      final reported = await dartBeforeSend(bareWorkerEvent, Hint());

      expect(
        reported?.eventId,
        bareWorkerEvent.eventId,
        reason: 'send the original worker report',
      );
      expect(
        [reported!.exceptions?.single.value, reported.message?.formatted],
        anyElement(allOf(isNot(originalValue), contains('drift_worker.js'))),
        reason: 'replace the bare text or add a diagnostic message',
      );
    },
  );
}
