import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
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
}
