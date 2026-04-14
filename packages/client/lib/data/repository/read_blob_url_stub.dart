import 'dart:typed_data';

/// Only used on web; VM should not call [readBlobUrlBytes] for blob URLs.
Future<Uint8List> readBlobUrlBytes(String blobUrl) async {
  throw UnsupportedError('readBlobUrlBytes is web-only');
}
