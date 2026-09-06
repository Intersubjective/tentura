import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_notice.dart';
import 'package:tentura/ui/l10n/l10n.dart';

RoomMessage _message({
  required String body,
  int? systemMessageKind,
  Map<String, Object?>? payload,
}) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'System actor'),
  body: body,
  createdAt: DateTime.utc(2026, 1, 1),
  systemMessageKind: systemMessageKind,
  systemPayloadJson: payload == null ? null : jsonEncode(payload),
);

Widget _harness(RoomMessage message) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: BeaconHierarchyNotice(message: message),
  ),
);

void main() {
  group('isHierarchyNoticeRow', () {
    test('true for both known discriminator values', () {
      expect(
        BeaconHierarchyNotice.isHierarchyNoticeRow(
          _message(
            body: '',
            systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
          ),
        ),
        isTrue,
      );
      expect(
        BeaconHierarchyNotice.isHierarchyNoticeRow(
          _message(
            body: '',
            systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
          ),
        ),
        isTrue,
      );
    });

    test('false for an ordinary message', () {
      expect(
        BeaconHierarchyNotice.isHierarchyNoticeRow(_message(body: 'hi')),
        isFalse,
      );
    });
  });

  group('BeaconHierarchyNotice', () {
    testWidgets('lifecycle notice shows the server-generated body verbatim', (
      tester,
    ) async {
      const dated = 'An ancestor request was closed on 2026-01-04';
      await tester.pumpWidget(
        _harness(
          _message(
            body: dated,
            systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
            payload: {
              'version': 1,
              'kind': 'hierarchyLifecycle',
              'eventId': 'e1',
              'targetBeaconId': 'b1',
              'direction': 'ancestor',
              'toStatus': 'closed',
              'occurredAt': '2026-01-04T00:00:00Z',
              'sourceDeleted': false,
            },
          ),
        ),
      );

      expect(find.text(dated), findsOneWidget);
    });

    testWidgets('creation notice shows fixed copy, ignoring empty body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _message(
            body: '',
            systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
            payload: {
              'version': 1,
              'kind': 'childCreated',
              'childBeaconId': 'child-1',
            },
          ),
        ),
      );
      await tester.pump();

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.beaconHierarchyNoticeChildCreated), findsOneWidget);
    });

    testWidgets('unparseable payload falls back to generic, non-actionable text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _message(
            body: 'should be ignored',
            systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
            payload: {'version': 2, 'kind': 'somethingNew'},
          ),
        ),
      );
      await tester.pump();

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.beaconHierarchyNoticeUnknown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing payload entirely falls back to generic text without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _message(
            body: '',
            systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
          ),
        ),
      );
      await tester.pump();

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.beaconHierarchyNoticeUnknown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes a semantics label matching the displayed line', (
      tester,
    ) async {
      const dated = 'A child request was cancelled on 2026-02-02';
      await tester.pumpWidget(
        _harness(
          _message(
            body: dated,
            systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
            payload: {
              'version': 1,
              'kind': 'hierarchyLifecycle',
              'eventId': 'e2',
              'targetBeaconId': 'b1',
              'direction': 'child',
              'toStatus': 'cancelled',
              'occurredAt': '2026-02-02T00:00:00Z',
              'sourceDeleted': false,
            },
          ),
        ),
      );

      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(
        semantics.any((s) => s.properties.label == dated),
        isTrue,
      );
    });

    testWidgets('renders no author avatar/identity chrome (person-free notice)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _message(
            body: 'text',
            systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
            payload: {
              'version': 1,
              'kind': 'hierarchyLifecycle',
              'eventId': 'e3',
              'targetBeaconId': 'b1',
              'direction': 'ancestor',
              'toStatus': 'closed',
              'occurredAt': '2026-01-04T00:00:00Z',
              'sourceDeleted': false,
            },
          ),
        ),
      );

      expect(find.byType(TenturaAvatar), findsNothing);
      expect(find.text('System actor'), findsNothing);
    });
  });
}
