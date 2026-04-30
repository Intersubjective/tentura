import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';

void main() {
  test('parseRoomMessageAttachmentsJson sorts by position', () {
    const raw =
        '[{"position":1,"id":"b","kind":2,"mime":"application/pdf","sizeBytes":3,"fileName":"a.pdf"},'
        '{"position":0,"id":"a","kind":1,"mime":"image/jpeg","sizeBytes":9,"fileName":"","imageId":"i","imageAuthorId":"u","blurHash":"x","width":2,"height":2}]';
    final list = parseRoomMessageAttachmentsJson(raw);
    expect(list.length, 2);
    expect(list[0].id, 'a');
    expect(list[0].position, 0);
    expect(list[0].kind, BeaconRoomMessageAttachmentKind.image);
    expect(list[1].id, 'b');
    expect(list[1].isFile, true);
  });

  test('parseRoomMessageAttachmentsJson rejects malformed maps', () {
    expect(parseRoomMessageAttachmentsJson('[{}]').length, 0);
    expect(parseRoomMessageAttachmentsJson('null'), isEmpty);
  });
}
