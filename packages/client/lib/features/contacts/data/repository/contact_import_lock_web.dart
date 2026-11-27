import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<T> withContactImportLock<T>(String key, Future<T> Function() run) async {
  late Future<T> result;
  await web.window.navigator.locks
      .request(
        key,
        ((web.Lock? _) {
          result = Future.sync(run);
          // Keep the browser lock until the operation settles. Surface Dart
          // errors through result so callers receive the original exception.
          return result
              .then<JSAny?>((_) => null, onError: (Object _) => null)
              .toJS;
        }).toJS,
      )
      .toDart;
  return result;
}
