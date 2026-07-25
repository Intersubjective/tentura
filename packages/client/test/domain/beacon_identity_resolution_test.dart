import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_cover.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

const _image = ImageEntity(id: 'img-1', authorId: 'author-1');
const _otherImage = ImageEntity(id: 'img-2', authorId: 'author-1');

Beacon _beacon({
  String? primaryNeedSlug,
  Set<String> needs = const {},
  List<ImageEntity> images = const [],
  String? coverImageId,
  BeaconCoverSource coverSource = BeaconCoverSource.photo,
  bool canReadContent = true,
}) =>
    Beacon.empty.copyWith(
      id: 'beacon-1',
      title: 'Request title',
      author: const Profile(id: 'author-1'),
      needs: needs,
      images: images,
      primaryNeedSlug: primaryNeedSlug,
      coverImageId: coverImageId,
      coverSource: coverSource,
      canReadContent: canReadContent,
    );

void main() {
  group('resolveIdentity(allowPhoto: true)', () {
    test('photo source with an attached selected cover resolves to photo', () {
      final identity = _beacon(
        images: const [_otherImage, _image],
        coverImageId: 'img-1',
        needs: const {'transport'},
        primaryNeedSlug: 'transport',
      ).identity;

      expect(identity, const BeaconIdentityPhoto(_image));
    });

    test('symbol source keeps the stored photo but resolves to symbol', () {
      final identity = _beacon(
        images: const [_image],
        coverImageId: 'img-1',
        coverSource: BeaconCoverSource.symbol,
        needs: const {'transport'},
        primaryNeedSlug: 'transport',
      ).identity;

      expect(identity, const BeaconIdentitySymbol(CapabilityTag.transport));
    });

    test('stale cover id falls back to the primary symbol', () {
      final identity = _beacon(
        images: const [_otherImage],
        coverImageId: 'img-1',
        needs: const {'housing'},
        primaryNeedSlug: 'housing',
      ).identity;

      expect(identity, const BeaconIdentitySymbol(CapabilityTag.housing));
    });

    test('stale cover id with no valid primary resolves to neutral', () {
      final identity = _beacon(
        images: const [_otherImage],
        coverImageId: 'img-1',
      ).identity;

      expect(identity, const BeaconIdentityNeutral());
    });

    test('photo source with no images resolves to the primary symbol', () {
      final identity = _beacon(
        needs: const {'childcare'},
        primaryNeedSlug: 'childcare',
      ).identity;

      expect(identity, const BeaconIdentitySymbol(CapabilityTag.childcare));
    });

    test('primary absent from needs resolves to neutral', () {
      final identity = _beacon(
        needs: const {'housing'},
        primaryNeedSlug: 'transport',
      ).identity;

      expect(identity, const BeaconIdentityNeutral());
    });

    test('unknown primary slug resolves to neutral', () {
      final identity = _beacon(
        needs: const {'not_a_capability'},
        primaryNeedSlug: 'not_a_capability',
      ).identity;

      expect(identity, const BeaconIdentityNeutral());
    });

    test('empty needs with a null primary resolves to neutral', () {
      expect(_beacon().identity, const BeaconIdentityNeutral());
    });

    test('unreadable content resolves to neutral before any other branch', () {
      final identity = _beacon(
        images: const [_image],
        coverImageId: 'img-1',
        needs: const {'transport'},
        primaryNeedSlug: 'transport',
        canReadContent: false,
      ).identity;

      expect(identity, const BeaconIdentityNeutral());
    });
  });

  group('resolveIdentity(allowPhoto: false)', () {
    test('a valid photo cover degrades to the primary symbol', () {
      final identity = _beacon(
        images: const [_image],
        coverImageId: 'img-1',
        needs: const {'food'},
        primaryNeedSlug: 'food',
      ).resolveIdentity(allowPhoto: false);

      expect(identity, const BeaconIdentitySymbol(CapabilityTag.food));
    });

    test('a valid photo cover with no primary degrades to neutral', () {
      final identity = _beacon(
        images: const [_image],
        coverImageId: 'img-1',
      ).resolveIdentity(allowPhoto: false);

      expect(identity, const BeaconIdentityNeutral());
    });
  });

  group('coverImage', () {
    test('is null when no cover is selected', () {
      expect(_beacon(images: const [_image]).coverImage, isNull);
    });

    test('is null when the selection is not attached', () {
      expect(
        _beacon(images: const [_otherImage], coverImageId: 'img-1').coverImage,
        isNull,
      );
    });

    test('is the attached image when the selection is valid', () {
      expect(
        _beacon(
          images: const [_otherImage, _image],
          coverImageId: 'img-1',
        ).coverImage,
        _image,
      );
    });
  });
}
