import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

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
  final previousFn =
      previous != null && previous.isA<JSFunction>() ? previous as JSFunction : null;

  final wrapped = ((JSAny? event, JSAny? hint) {
    if (event != null && event.isA<JSObject>()) {
      final eventObj = event as JSObject;
      if (_shouldDropOpaqueScriptError(eventObj)) {
        return null;
      }
    }

    if (previousFn != null) {
      return previousFn.callAsFunction(optionsObj, event, hint);
    }
    return event;
  }).toJS;

  optionsObj.setProperty('beforeSend'.toJS, wrapped);
  optionsObj.setProperty(_filterInstalledKey.toJS, true.toJS);
}

bool _shouldDropOpaqueScriptError(JSObject event) {
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

  final exceptionValues = _readExceptionValues(event);

  return isOpaqueBrowserScriptErrorEvent(
    message: message,
    messageFormatted: messageFormatted,
    messageObjectMessage: messageObjectMessage,
    exceptionValues: exceptionValues,
  );
}

String? _readJsString(JSObject object, String key) {
  final value = object.getProperty(key.toJS);
  if (value == null || !value.isA<JSString>()) {
    return null;
  }
  return (value as JSString).toDart;
}

List<String?> _readExceptionValues(JSObject event) {
  final exception = event.getProperty('exception'.toJS);
  if (exception == null || !exception.isA<JSObject>()) {
    return const [];
  }

  final values = (exception as JSObject).getProperty('values'.toJS);
  if (values == null || !values.isA<JSArray>()) {
    return const [];
  }

  final array = values as JSArray;
  final result = <String?>[];
  for (var i = 0; i < array.length; i++) {
    final item = array[i];
    if (item != null && item.isA<JSObject>()) {
      result.add(_readJsString(item as JSObject, 'value'));
    }
  }
  return result;
}
