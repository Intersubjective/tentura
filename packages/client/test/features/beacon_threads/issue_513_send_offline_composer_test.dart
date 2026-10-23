import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_threads/domain/entity/committed_mention.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/room_body_harness.dart';

/// One scripted answer to a send: what `sendMessage` returns and whether the
/// cubit reports the failure as "offline".
typedef _SendOutcome = ({bool sent, bool offline, bool unconfirmed});

/// Harness cubit whose `sendMessage` records the body and plays back
/// scripted outcomes, the way the real cubit sets `sendFailedOffline`.
///
/// When [gates] holds a completer at a send's index, that send stays pending
/// until the test completes it.
class _ScriptedSendCubit extends RoomBodyHarnessCubit {
  _ScriptedSendCubit(super.initial, this.outcomes, {this.gates = const {}});

  final List<_SendOutcome> outcomes;
  final Map<int, Completer<void>> gates;
  final sentBodies = <String>[];

  @override
  Future<bool> sendMessage({
    required String body,
    List<RoomPendingUpload> uploads = const [],
    List<CommittedMention> explicitMentions = const [],
  }) async {
    final index = sentBodies.length;
    sentBodies.add(body);
    final next = outcomes.removeAt(0);
    final gate = gates[index];
    if (gate != null) {
      await gate.future;
    }
    emitHarnessState(
      state.copyWith(
        sendFailedOffline: next.offline,
        sendUnconfirmed: next.unconfirmed,
      ),
    );
    return next.sent;
  }
}

Finder _composerField() => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composerField()).controller?.text ?? '';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('issue #513 composer shows a message that did not send offline', () {
    testWidgets('an offline failure keeps the text, shows Not sent with Retry, '
        'and Retry sends the same text once even when tapped twice', (
      tester,
    ) async {
      final initial = roomBodyState();
      final retryGate = Completer<void>();
      final cubit = _ScriptedSendCubit(
        initial,
        [
          (sent: false, offline: true, unconfirmed: false),
          (sent: true, offline: false, unconfirmed: false),
        ],
        gates: {1: retryGate},
      );
      await pumpBeaconRoomBody(tester, roomState: initial, cubit: cubit);
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomSendFailedOffline), findsNothing);

      await tester.enterText(_composerField(), 'see you at 6');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(cubit.sentBodies, ['see you at 6']);
      expect(_composerText(tester), 'see you at 6');
      expect(find.text(l10n.beaconRoomSendFailedOffline), findsOneWidget);
      expect(find.text(l10n.beaconRoomSendRetry), findsOneWidget);

      // The retry send stays pending; a second tap must not send again.
      await tester.tap(find.text(l10n.beaconRoomSendRetry));
      await tester.pump();
      if (find.text(l10n.beaconRoomSendRetry).evaluate().isNotEmpty) {
        await tester.tap(
          find.text(l10n.beaconRoomSendRetry),
          warnIfMissed: false,
        );
        await tester.pump();
      }

      expect(cubit.sentBodies, ['see you at 6', 'see you at 6']);

      retryGate.complete();
      await tester.pumpAndSettle();

      expect(cubit.sentBodies, ['see you at 6', 'see you at 6']);
      expect(_composerText(tester), isEmpty);
      expect(find.text(l10n.beaconRoomSendFailedOffline), findsNothing);
      expect(find.text(l10n.beaconRoomSendRetry), findsNothing);
    });

    // #654: a timed-out send may be saved; Retry reuses its idempotency key.
    testWidgets('a timed-out send shows Not confirmed with Retry, not the '
        'offline line', (tester) async {
      final initial = roomBodyState();
      final cubit = _ScriptedSendCubit(initial, [
        (sent: false, offline: false, unconfirmed: true),
        (sent: true, offline: false, unconfirmed: false),
      ]);
      await pumpBeaconRoomBody(tester, roomState: initial, cubit: cubit);
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'see you at 6');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(_composerText(tester), 'see you at 6');
      expect(find.text(l10n.beaconRoomSendUnconfirmed), findsOneWidget);
      expect(find.text(l10n.beaconRoomSendFailedOffline), findsNothing);
      expect(find.byIcon(Icons.sync_problem_outlined), findsOneWidget);

      await tester.tap(find.text(l10n.beaconRoomSendRetry));
      await tester.pumpAndSettle();

      expect(cubit.sentBodies, ['see you at 6', 'see you at 6']);
      expect(find.text(l10n.beaconRoomSendUnconfirmed), findsNothing);
      expect(_composerText(tester), isEmpty);
    });

    testWidgets('editing the kept text hides the Not sent notice', (
      tester,
    ) async {
      final initial = roomBodyState();
      final cubit = _ScriptedSendCubit(initial, [
        (sent: false, offline: true, unconfirmed: false),
      ]);
      await pumpBeaconRoomBody(tester, roomState: initial, cubit: cubit);
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'see you at 6');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomSendFailedOffline), findsOneWidget);
      expect(find.text(l10n.beaconRoomSendRetry), findsOneWidget);

      await tester.enterText(_composerField(), 'see you at 7');
      await tester.pumpAndSettle();

      expect(cubit.sentBodies, ['see you at 6']);
      expect(_composerText(tester), 'see you at 7');
      expect(find.text(l10n.beaconRoomSendFailedOffline), findsNothing);
      expect(find.text(l10n.beaconRoomSendRetry), findsNothing);
    });

    testWidgets('after an offline failure, sending again with the send button '
        'sends the same text once and clears the notice', (tester) async {
      final initial = roomBodyState();
      final cubit = _ScriptedSendCubit(initial, [
        (sent: false, offline: true, unconfirmed: false),
        (sent: true, offline: false, unconfirmed: false),
      ]);
      await pumpBeaconRoomBody(tester, roomState: initial, cubit: cubit);
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'see you at 6');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomSendFailedOffline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(cubit.sentBodies, ['see you at 6', 'see you at 6']);
      expect(_composerText(tester), isEmpty);
      expect(find.text(l10n.beaconRoomSendFailedOffline), findsNothing);
      expect(find.text(l10n.beaconRoomSendRetry), findsNothing);
    });

    testWidgets('a refused send keeps the text without the offline notice', (
      tester,
    ) async {
      final initial = roomBodyState();
      final cubit = _ScriptedSendCubit(initial, [
        (sent: false, offline: false, unconfirmed: false),
      ]);
      await pumpBeaconRoomBody(tester, roomState: initial, cubit: cubit);
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'see you at 6');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(cubit.sentBodies, ['see you at 6']);
      expect(_composerText(tester), 'see you at 6');
      expect(find.text(l10n.beaconRoomSendFailedOffline), findsNothing);
      expect(find.text(l10n.beaconRoomSendRetry), findsNothing);
    });
  });
}
