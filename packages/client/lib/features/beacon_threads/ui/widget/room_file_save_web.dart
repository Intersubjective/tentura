import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] through a browser download named [name] (no share sheet).
Future<void> saveRoomFile(Uint8List bytes, String name, String mime) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = name
    ..click();
  // Revoke later: the browser may read the blob after click() returns.
  web.window.setTimeout(
    (() => web.URL.revokeObjectURL(url)).toJS,
    60000.toJS,
  );
}
