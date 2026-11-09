import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:tentura_server/consts.dart';

/// Content-addressed S3 object key for room file attachments.
String roomAttachmentStorageKey(Uint8List bytes) {
  final hash = sha256.convert(bytes);
  return '$kRoomAttachmentsPath/$hash';
}
