import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/util/room_attachment_storage_key.dart';

void main() {
  test('roomAttachmentStorageKey is content-addressed under room_attachments', () {
    final bytes = Uint8List.fromList('plain text content'.codeUnits);
    final hash = sha256.convert(bytes).toString();
    expect(
      roomAttachmentStorageKey(bytes),
      '$kRoomAttachmentsPath/$hash',
    );
  });
}
