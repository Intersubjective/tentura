import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'drift_worker_error.dart';
import 'opaque_script_error.dart';

const _filterInstalledKey = '__tenturaScriptErrorFilter';

void installWebScriptErrorFilter() {
  final global = web.window as JSObject;
  final sentry = global.getProperty('Sentry'.toJS);
  if (sentry == null || !sentry.isA<JSObject>()) {
    return;
  }

  final sentryObj = sentry as JSObject;
  final getClientFn = sentryObj.getProperty('getClient'.toJS);
  if (getClientFn == null || !getClientFn.isA<JSFunction>()) {
    return;
  }

  final client = (getClientFn as JSFunction).callAsFunction(sentryObj);
  if (client == null || !client.isA<JSObject>()) {
    return;
  }

  final clientObj = client as JSObject;
  final getOptionsFn = clientObj.getProperty('getOptions'.toJS);
  if (getOptionsFn == null || !getOptionsFn.isA<JSFunction>()) {
    return;
  }

  final options = (getOptionsFn as JSFunction).callAsFunction(clientObj);
  if (options == null || !options.isA<JSObject>()) {
    return;
  }

  final optionsObj = options as JSObject;
  final installed = optionsObj.getProperty(_filterInstalledKey.toJS);
  if (installed != null &&
      installed.isA<JSBoolean>() &&
      (installed as JSBoolean).toDart) {
    return;
  }

  final previous = optionsObj.getProperty('beforeSend'.toJS);
  final previousFn = previous != null && previous.isA<JSFunction>()
      ? previous as JSFunction
      : null;

  final wrapped = ((JSAny? event, JSAny? hint) {
    if (event != null && event.isA<JSObject>()) {
      final eventObj = event as JSObject;
      final exceptions = _readJsArray(
        _readJsObject(eventObj, 'exception'),
        'values',
      );
      if (_shouldDropOpaqueScriptError(eventObj, exceptions)) {
        return null;
      }
      if (exceptions case [final rawException]) {
        final exception = _asJsObject(rawException);
        if (exception != null) {
          _annotateDriftWorkerError(exception);
        }
      }
    }

    if (previousFn != null) {
      return previousFn.callAsFunction(optionsObj, event, hint);
    }
    return event;
  }).toJS;

  optionsObj
    ..setProperty('beforeSend'.toJS, wrapped)
    ..setProperty(_filterInstalledKey.toJS, true.toJS);
}

bool _shouldDropOpaqueScriptError(JSObject event, List<JSAny?> exceptions) {
  String? message;
  String? messageFormatted;
  String? messageObjectMessage;

  final rawMessage = event.getProperty('message'.toJS);
  if (rawMessage != null) {
    if (rawMessage.isA<JSString>()) {
      message = (rawMessage as JSString).toDart;
    } else if (rawMessage.isA<JSObject>()) {
      final messageObj = rawMessage as JSObject;
      messageFormatted = _readJsString(messageObj, 'formatted');
      messageObjectMessage = _readJsString(messageObj, 'message');
    }
  }

  return isOpaqueBrowserScriptErrorEvent(
    message: message,
    messageFormatted: messageFormatted,
    messageObjectMessage: messageObjectMessage,
    exceptionValues: exceptions.map(
      (exception) => _readJsString(_asJsObject(exception), 'value'),
    ),
  );
}

void _annotateDriftWorkerError(JSObject exception) {
  final diagnostic = driftWorkerErrorDiagnostic(
    type: _readJsString(exception, 'type'),
    value: _readJsString(exception, 'value'),
    mechanism: _readJsString(_readJsObject(exception, 'mechanism'), 'type'),
    framePaths: () => _readJsArray(
      _readJsObject(exception, 'stacktrace'),
      'frames',
    ).map((frame) => _readJsString(_asJsObject(frame), 'abs_path')),
  );
  if (diagnostic != null) {
    exception.setProperty('value'.toJS, diagnostic.toJS);
  }
}

String? _readJsString(JSObject? object, String key) {
  final value = object?.getProperty<JSAny?>(key.toJS);
  if (value == null || !value.isA<JSString>()) {
    return null;
  }
  return (value as JSString).toDart;
}

JSObject? _asJsObject(JSAny? value) =>
    value != null && value.isA<JSObject>() ? value as JSObject : null;

JSObject? _readJsObject(JSObject object, String key) =>
    _asJsObject(object.getProperty<JSAny?>(key.toJS));

List<JSAny?> _readJsArray(JSObject? object, String key) {
  final value = object?.getProperty<JSAny?>(key.toJS);
  return value != null && value.isA<JSArray>()
      ? (value as JSArray).toDart
      : const [];
}
