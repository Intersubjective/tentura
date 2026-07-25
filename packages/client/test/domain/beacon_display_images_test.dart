import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

const _first = ImageEntity(id: 'img-1', authorId: 'author-1');
const _second = ImageEntity(id: 'img-2', authorId: 'author-1');
const _third = ImageEntity(id: 'img-3', authorId: 'author-1');

Beacon _beacon({
  List<ImageEntity> images = const [_first, _second, _third],
  String? coverImageId,
  BeaconCoverSource coverSource = BeaconCoverSource.photo,
}) =>
    Beacon.empty.copyWith(
      id: 'beacon-1',
      author: const Profile(id: 'author-1'),
      images: images,
      coverImageId: coverImageId,
      coverSource: coverSource,
    );

String _url(String imageId) =>
    '$kImageServer/$kImagesPath/author-1/$imageId.$kImageExt';

void main() {
  test('a non-first cover leads the projection, others keep order', () {
    final beacon = _beacon(coverImageId: 'img-3');

    expect(
      beacon.displayImages.map((e) => e.id),
      ['img-3', 'img-1', 'img-2'],
    );
    expect(
      beacon.displayImageUrls,
      [_url('img-3'), _url('img-1'), _url('img-2')],
    );
  });

  test('a missing cover keeps persisted order', () {
    final beacon = _beacon(coverImageId: 'img-missing');

    expect(beacon.displayImages.map((e) => e.id), ['img-1', 'img-2', 'img-3']);
  });

  test('symbol source still projects the cover first for the gallery', () {
    final beacon = _beacon(
      coverImageId: 'img-2',
      coverSource: BeaconCoverSource.symbol,
    );

    expect(beacon.displayImages.map((e) => e.id), ['img-2', 'img-1', 'img-3']);
  });

  test('urls stay aligned index-for-index with objects', () {
    final beacon = _beacon(coverImageId: 'img-2');
    final images = beacon.displayImages;
    final urls = beacon.displayImageUrls;

    expect(urls.length, images.length);
    for (var i = 0; i < images.length; i++) {
      expect(urls[i], _url(images[i].id));
    }
  });

  test('imageUrl is the cover-first thumbnail', () {
    expect(_beacon(coverImageId: 'img-3').imageUrl, _url('img-3'));
  });

  test('imageUrl is the placeholder with no images', () {
    expect(_beacon(images: const []).imageUrl, kBeaconPlaceholderUrl);
  });

  test('legacy imageUrls alias uses the same ordered projection', () {
    final beacon = _beacon(coverImageId: 'img-3');

    expect(beacon.imageUrls, beacon.displayImageUrls);
  });
}
