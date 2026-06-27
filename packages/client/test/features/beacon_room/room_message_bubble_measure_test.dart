import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_bubble_measure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const countStyle = TextStyle(fontSize: 12);

  double measure({required int count, required bool hasUnread}) =>
      measureLifecycleThreadMarkWidth(
        count: count,
        hasUnread: hasUnread,
        countStyle: countStyle,
        itemGap: 8,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      );

  group('measureLifecycleThreadMarkWidth', () {
    test('reserves room for the forum mark even with no replies', () {
      expect(measure(count: 0, hasUnread: false), greaterThan(0));
    });

    test('grows when a reply count is shown', () {
      expect(
        measure(count: 3, hasUnread: false),
        greaterThan(measure(count: 0, hasUnread: false)),
      );
    });

    test('grows further when an unread dot is shown', () {
      expect(
        measure(count: 3, hasUnread: true),
        greaterThan(measure(count: 3, hasUnread: false)),
      );
    });
  });
}
