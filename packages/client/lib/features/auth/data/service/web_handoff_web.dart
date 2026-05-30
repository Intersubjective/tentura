import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'handoff_codec.dart';
import 'handoff_payload.dart';

/// The raw URL fragment captured by `web/index.html` BEFORE Flutter's hash URL
/// strategy normalized it away.
@JS('__tenturaHandoff')
external JSString? _capturedHandoff;

/// Reads and decodes the landing -> app session-handoff payload, if present.
HandoffPayload? readHandoff() => decodeHandoffFragment(_capturedHandoff?.toDart);

///
/// Clears the captured fragment from memory and drops it from the URL/history
/// (the inline `web/index.html` script already scrubs the address bar; this is
/// idempotent belt-and-suspenders).
///
void scrubHandoff() {
  _capturedHandoff = null;
  final location = web.window.location;
  web.window.history.replaceState(
    null,
    '',
    '${location.pathname}${location.search}',
  );
}
