import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

import '../../support/phone_surface.dart';
import 'support/room_body_harness.dart';

const _typist = Profile(id: 'peer', displayName: 'Борис');
const _newestBody = 'Последнее сообщение\nВторая строка\nКонец сообщения';

Future<RoomBodyHarnessCubit> _openDiscussion(WidgetTester tester) async {
  await usePhoneSurface(tester);
  final cubit = await pumpBeaconRoomBody(
    tester,
    width: kPhoneSurface.width,
    height: kPhoneSurface.height,
    locale: const Locale('ru'),
    roomState:
        roomBodyState(
          messages: [
            for (var i = 0; i < 24; i++)
              RoomMessage(
                id: 'message-$i',
                beaconId: 'b1',
                authorId: _typist.id,
                author: _typist,
                body: i == 23 ? _newestBody : 'Сообщение $i',
                createdAt: DateTime.utc(2026, 11, 1, 12, i),
              ),
          ],
        ).copyWith(
          participantsLoaded: true,
          participants: [
            roomBodyAdmittedParticipant(beaconId: 'b1', profile: _typist),
          ],
        ),
  );
  await pumpUntilViewportDone(tester);
  final scrollable = listScrollableState(tester);
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  return cubit;
}

void _expectNewestInsideViewport(WidgetTester tester) {
  final newest = find.byWidgetPredicate(
    (widget) => widget is RoomMessageTile && widget.message.body == _newestBody,
  );
  expect(newest, findsOneWidget);
  final messageRect = tester.getRect(newest);
  final viewport = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Viewport),
  );
  expect(viewport, findsOneWidget);
  final viewportRect = tester.getRect(viewport);
  final typing = find.text('Борис печатает…');
  var effectiveBottom = viewportRect.bottom;
  if (typing.evaluate().isNotEmpty) {
    final typingRect = tester.getRect(typing);
    expect(
      messageRect.overlaps(typingRect),
      isFalse,
      reason:
          'the rendered typing line must not cover any part of the newest message',
    );
    if (typingRect.top < effectiveBottom) effectiveBottom = typingRect.top;
  }
  expect(messageRect.top, greaterThanOrEqualTo(viewportRect.top));
  expect(
    messageRect.bottom,
    lessThanOrEqualTo(effectiveBottom),
    reason: 'the entire newest message tile stays above the typing line',
  );
  expect(messageRect.left, greaterThanOrEqualTo(viewportRect.left));
  expect(messageRect.right, lessThanOrEqualTo(viewportRect.right));
  expect(tester.takeException(), isNull);
}

void main() => runRoomTypingVisibilityTests();

/// The browser integration target runs the same production-widget scenario
/// and additionally checks the browser's exported accessibility DOM.
void runRoomTypingVisibilityTests({
  Future<void> Function(WidgetTester tester, String label, bool visible)?
  verifyBrowserSemantics,
}) {
  testWidgets(
    'the newest message stays fully visible and typing text is accessible on a Russian phone',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final cubit = await _openDiscussion(tester);
        _expectNewestInsideViewport(tester);
        const label = 'Борис печатает…';
        expect(find.bySemanticsLabel(label), findsNothing);

        cubit.emitHarnessState(
          cubit.state.copyWith(typingUserIds: [_typist.id]),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(
          find.bySemanticsLabel(label),
          findsOneWidget,
          reason:
              'the active typing line must be exposed to assistive technology',
        );
        await verifyBrowserSemantics?.call(tester, label, true);
        _expectNewestInsideViewport(tester);

        cubit.emitHarnessState(cubit.state.copyWith(typingUserIds: const []));
        await tester.pumpAndSettle();
        expect(find.text(label), findsNothing);
        expect(find.bySemanticsLabel(label), findsNothing);
        await verifyBrowserSemantics?.call(tester, label, false);
        _expectNewestInsideViewport(tester);
      } finally {
        semantics.dispose();
      }
    },
  );
}
