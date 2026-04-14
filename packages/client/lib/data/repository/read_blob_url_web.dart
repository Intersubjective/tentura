import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Read blob: URL bytes on Flutter web via the Fetch API.
Future<Uint8List> readBlobUrlBytes(String blobUrl) async {
  final response = await web.window.fetch(blobUrl.toJS).toDart;
  final arrayBuffer = await response.arrayBuffer().toDart;
  return arrayBuffer.toDart.asUint8List();
}
