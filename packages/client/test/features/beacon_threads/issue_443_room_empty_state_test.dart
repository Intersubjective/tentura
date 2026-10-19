// Issue #443: an empty Request room must not be a blank void — the chat
// column shows a one-line empty state (l10n key `beaconRoomEmptyState`, en+ru)
// while the composer stays usable. Loading, error and non-empty rooms keep
// their existing content and never show the empty state.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'support/room_body_harness.dart';

const _key = 'beaconRoomEmptyState';
const _viewer = Profile(id: 'me', displayName: 'Me');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

String _copy(String locale) {
  final value = _arb(locale)[_key];
  expect(
    value,
    isA<String>(),
    reason: 'app_$locale.arb needs a "$_key" entry (issue #443)',
  );
  return value as String;
}

void main() {
  group('#443 empty Request room', () {
    test('empty-state copy exists in every locale and is translated', () {
      final en = _copy('en');
      final ru = _copy('ru');
      expect(en, contains('No messages yet'));
      expect(en.contains('\n'), isFalse, reason: 'one line of copy');
      expect(ru, isNot(en));
      expect(RegExp('[а-яА-ЯёЁ]').hasMatch(ru), isTrue);
    });

    testWidgets('desktop: empty loaded room shows the one-line empty state', (
      tester,
    ) async {
      final copy = _copy('en');
      await pumpBeaconRoomBody(
        tester,
        width: 1280,
        height: 800,
        roomState: roomBodyState(),
      );
      await tester.pump();

      expect(find.text(copy), findsOneWidget);
      // The composer is still there under the empty state.
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile: empty loaded room shows the empty state in Russian', (
      tester,
    ) async {
      final ru = _copy('ru');
      await pumpBeaconRoomBody(
        tester,
        locale: const Locale('ru'),
        roomState: roomBodyState(),
      );
      await tester.pump();

      expect(find.text(ru), findsOneWidget);
      expect(find.text(_copy('en')), findsNothing);
    });

    testWidgets('a room with a message does not show the empty state', (
      tester,
    ) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: roomBodyState(
          messages: [
            RoomMessage(
              id: 'm1',
              beaconId: 'b1',
              authorId: _viewer.id,
              author: _viewer,
              body: 'First coordination message',
              createdAt: DateTime.utc(2026, 10, 19, 12),
            ),
          ],
        ),
      );
      await pumpUntilViewportDone(tester);

      // The tile body is Text.rich with inline trailing meta, so match the
      // RichText by containment (same pattern as the b084 room-line tests).
      expect(
        find.textContaining('First coordination message', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('No messages yet'), findsNothing);
    });

    testWidgets('a loading room shows the spinner, not the empty state', (
      tester,
    ) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: roomBodyState().copyWith(status: const StateIsLoading()),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.textContaining('No messages yet'), findsNothing);
    });

    testWidgets('a failed load shows the error, not the empty state', (
      tester,
    ) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: roomBodyState().copyWith(loadError: 'room load failed'),
      );
      await tester.pump();

      expect(find.text('room load failed'), findsOneWidget);
      expect(find.textContaining('No messages yet'), findsNothing);
    });
  });
}
