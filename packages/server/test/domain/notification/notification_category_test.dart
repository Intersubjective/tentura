import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';

void main() {
  group('categoryOf', () {
    test('maps every kind to a category', () {
      for (final kind in NotificationKind.values) {
        // Must not throw (switch is exhaustive); records the mapping.
        expect(categoryOf(kind), isA<NotificationCategory>());
      }
    });

    test('asksOfMe groups the highest-stakes kinds', () {
      expect(categoryOf(NotificationKind.needsMe), NotificationCategory.asksOfMe);
      expect(
        categoryOf(NotificationKind.staleRemind),
        NotificationCategory.asksOfMe,
      );
      expect(
        categoryOf(NotificationKind.roomAccess),
        NotificationCategory.asksOfMe,
      );
    });

    test('unblocksMe groups resolutions', () {
      expect(
        categoryOf(NotificationKind.blockerResolved),
        NotificationCategory.unblocksMe,
      );
      expect(
        categoryOf(NotificationKind.reviewReady),
        NotificationCategory.unblocksMe,
      );
    });

    test('coordination groups awareness kinds', () {
      expect(
        categoryOf(NotificationKind.promiseMade),
        NotificationCategory.coordination,
      );
      expect(
        categoryOf(NotificationKind.coordinationChanged),
        NotificationCategory.coordination,
      );
      expect(
        categoryOf(NotificationKind.blockerOpened),
        NotificationCategory.coordination,
      );
      expect(
        categoryOf(NotificationKind.commitmentEvent),
        NotificationCategory.coordination,
      );
      expect(
        categoryOf(NotificationKind.newRelay),
        NotificationCategory.coordination,
      );
    });

    test('ambient groups the background hum', () {
      expect(
        categoryOf(NotificationKind.roomActivityLowPriority),
        NotificationCategory.ambient,
      );
    });

    test('roomMention maps to coordination', () {
      expect(
        categoryOf(NotificationKind.roomMention),
        NotificationCategory.coordination,
      );
    });
  });

  group('notificationCategoryFromName', () {
    test('round-trips every category name', () {
      for (final c in NotificationCategory.values) {
        expect(notificationCategoryFromName(c.name), c);
      }
    });

    test('returns null for unknown name', () {
      expect(notificationCategoryFromName('nope'), isNull);
    });
  });
}
