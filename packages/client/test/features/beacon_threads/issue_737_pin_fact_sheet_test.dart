// #737: «Pin as fact» opened a sheet titled with the action's own name and
// two visibility choices, with no question saying what was being chosen and
// no Cancel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';

class _PinRecordingCubit extends RoomBodyHarnessCubit {
  _PinRecordingCubit(super.initial);

  final pins = <int>[];

  @override
  Future<void> pinFactFromMessage({
    required String sourceMessageId,
    required String factText,
    required int visibility,
  }) async {
    pins.add(visibility);
  }
}

void main() {
  const me = Profile(id: 'me', displayName: 'Me');
  final message = RoomMessage(
    id: 'm1',
    beaconId: 'b1',
    authorId: me.id,
    author: me,
    body: 'We meet at the gate',
    createdAt: DateTime.utc(2026, 10, 24, 12),
  );

  Future<_PinRecordingCubit> openPinSheet(
    WidgetTester tester,
    Locale locale,
  ) async {
    final l10n = lookupL10n(locale);
    final state = roomBodyState(messages: [message]);
    final cubit = _PinRecordingCubit(state);
    await pumpBeaconRoomBody(
      tester,
      roomState: state,
      cubit: cubit,
      height: 900,
      locale: locale,
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(
      tester.getTopLeft(find.byType(RoomMessageTextBody)) + const Offset(8, 8),
    );
    await tester.pumpAndSettle();
    final pin = find.text(l10n.beaconRoomActionPinFact);
    await tester.ensureVisible(pin);
    await tester.pumpAndSettle();
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconRoomPinFactPublic), findsOneWidget);
    return cubit;
  }

  for (final (locale, question) in const [
    (Locale('en'), 'Who can see this fact?'),
    (Locale('ru'), 'Кто увидит этот факт?'),
  ]) {
    testWidgets('the sheet asks who can see the fact ($locale)', (
      tester,
    ) async {
      await openPinSheet(tester, locale);

      expect(find.text(question), findsOneWidget);
    });
  }

  testWidgets('Cancel closes the sheet and pins nothing', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    final cubit = await openPinSheet(tester, const Locale('en'));

    await tester.tap(find.widgetWithText(TextButton, l10n.buttonCancel));
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconRoomPinFactPublic), findsNothing);
    expect(cubit.pins, isEmpty);
  });

  testWidgets('choosing Discussion only still pins once', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    final cubit = await openPinSheet(tester, const Locale('en'));

    await tester.tap(find.text(l10n.beaconRoomPinFactRoomOnly));
    await tester.pumpAndSettle();

    expect(cubit.pins, [BeaconFactCardVisibilityBits.room]);
  });
}
