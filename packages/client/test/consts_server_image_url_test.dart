import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart'
    show BeaconRoomMessageAttachmentKind;
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';

// Literal 'images' / 'jpg' on purpose: a change to kImagesPath or kImageExt
// must fail here, not silently move every image URL.
const _expected = '$kImageServer/images/U1/img42.jpg';

void main() {
  group('serverImageUrl', () {
    test('builds <server>/images/<authorId>/<imageId>.jpg', () {
      expect(serverImageUrl(authorId: 'U1', imageId: 'img42'), _expected);
    });

    test('passes ids through verbatim, no encoding', () {
      expect(
        serverImageUrl(authorId: 'a b/ü', imageId: 'x?y#z.png'),
        '$kImageServer/images/a b/ü/x?y#z.png.jpg',
      );
    });

    test('empty ids are not defaulted', () {
      expect(
        serverImageUrl(authorId: '', imageId: ''),
        '$kImageServer/images//.jpg',
      );
    });
  });

  group('caller parity', () {
    test('Profile.avatarUrl', () {
      expect(
        const Profile(id: 'U1', image: ImageEntity(id: 'img42')).avatarUrl,
        _expected,
      );
    });

    test('AccountEntity.avatarUrl', () {
      expect(
        const AccountEntity(id: 'U1', image: ImageEntity(id: 'img42'))
            .avatarUrl,
        _expected,
      );
    });

    test('Beacon.urlForImage uses the image authorId when set', () {
      final beacon = Beacon.empty.copyWith(author: const Profile(id: 'OTHER'));
      expect(
        beacon.urlForImage(const ImageEntity(id: 'img42', authorId: 'U1')),
        _expected,
      );
    });

    test('Beacon.urlForImage falls back to author.id when authorId is empty',
        () {
      final beacon = Beacon.empty.copyWith(author: const Profile(id: 'U1'));
      expect(beacon.urlForImage(const ImageEntity(id: 'img42')), _expected);
    });

    test('roomAttachmentImageUrl', () {
      const attachment = RoomMessageAttachment(
        id: 'a1',
        kind: BeaconRoomMessageAttachmentKind.image,
        position: 0,
        mime: 'image/jpeg',
        sizeBytes: 1,
        imageId: 'img42',
        imageAuthorId: 'U1',
      );
      expect(roomAttachmentImageUrl(attachment), _expected);
    });
  });
}
