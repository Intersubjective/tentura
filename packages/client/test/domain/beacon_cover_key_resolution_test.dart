import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/image_entity.dart';

void main() {
  test('a server image is identified by its id', () {
    const image = ImageEntity(id: 'img-1');

    expect(image.key, 'img-1');
  });

  test('a locally picked image is identified by its local key', () {
    const image = ImageEntity(localKey: 'local-abc');

    expect(image.key, 'local-abc');
  });

  test('a staged image prefers the returned server id over the local key', () {
    const picked = ImageEntity(localKey: 'local-abc');
    final staged = picked.copyWith(id: 'img-9');

    expect(staged.key, 'img-9');
  });

  test('key replacement matches by local key, never by list position', () {
    const images = [
      ImageEntity(id: 'img-1'),
      ImageEntity(localKey: 'local-b'),
      ImageEntity(localKey: 'local-c'),
    ];

    // The server returned an id for the *last* local entry first.
    final replaced = [
      for (final image in images)
        if (image.key == 'local-c') image.copyWith(id: 'img-7') else image,
    ];

    expect(replaced.map((e) => e.key), ['img-1', 'local-b', 'img-7']);
    expect(replaced[1].id, isEmpty);
  });

  test('an empty entity has an empty key', () {
    expect(const ImageEntity().key, isEmpty);
  });
}
