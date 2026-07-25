import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/beacon_gallery_viewer.dart';
import 'package:tentura/ui/widget/beacon_image_gallery.dart';

void main() {
  testWidgets(
    'uses its own PageStorage key under an expanded overview section',
    (tester) async {
      final bucket = PageStorageBucket();
      final beacon = Beacon.empty.copyWith(
        id: 'beacon-1',
        author: const Profile(id: 'author-1'),
        images: const [
          ImageEntity(id: 'image-1', width: 4, height: 3),
          ImageEntity(id: 'image-2', width: 4, height: 3),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PageStorage(
            bucket: bucket,
            child: KeyedSubtree(
              key: const PageStorageKey<String>('overview-description'),
              child: Builder(
                builder: (context) {
                  PageStorage.maybeOf(context)?.writeState(context, true);
                  return Scaffold(
                    body: BeaconImageGallery(
                      beacon: beacon,
                      maxHeight: 180,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PageView), findsOneWidget);
    },
  );

  testWidgets('page 0 is the selected cover, urls stay aligned', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'beacon-1',
      author: const Profile(id: 'author-1'),
      images: const [
        ImageEntity(id: 'image-1', width: 4, height: 3),
        ImageEntity(id: 'image-2', width: 4, height: 3),
        ImageEntity(id: 'image-3', width: 4, height: 3),
      ],
      coverImageId: 'image-3',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BeaconImageGallery(beacon: beacon, maxHeight: 180),
        ),
      ),
    );

    expect(beacon.displayImages.first.id, 'image-3');

    final rendered = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as NetworkImage).url)
        .toList();

    expect(rendered.first, beacon.displayImageUrls.first);
    expect(rendered.first, contains('image-3'));
  });

  testWidgets('viewer opens at the tapped projected index', (tester) async {
    final beacon = Beacon.empty.copyWith(
      id: 'beacon-1',
      author: const Profile(id: 'author-1'),
      images: const [
        ImageEntity(id: 'image-1', width: 4, height: 3),
        ImageEntity(id: 'image-2', width: 4, height: 3),
      ],
      coverImageId: 'image-2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BeaconImageGallery(beacon: beacon, maxHeight: 180),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    final viewer = tester.widget<BeaconGalleryViewer>(
      find.byType(BeaconGalleryViewer),
    );
    expect(viewer.initialIndex, 0);
    expect(
      viewer.beacon.displayImages[viewer.initialIndex].id,
      'image-2',
    );
  });
}
