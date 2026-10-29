// Unread Questions updates (messages other people posted in a Request's
// Questions) stay on the Requests card until the viewer actually opens
// Questions; opening Questions is what clears them.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit, RoomBodyHarnessProfileCubit;
import '../my_work/my_work_test_support.dart'
    show StubAttentionRepository, buildStubAttentionCase;
import 'fake_lobby_port.dart';

const _beaconId = 'B1';
const _questionReceiptId = 'question-Bob';

const _nina = Profile(id: 'Unina', displayName: 'Nina');

final class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: BeaconLobbyRoute.page, initial: true),
  ];
}

/// Remembers what each clear capture asked for: its reason and its target.
final class _RecordingAttention extends StubAttentionRepository {
  final captures =
      <({AttentionClearCaptureKind kind, String? beaconId, String? receiptId})>[];

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) {
    captures.add((kind: kind, beaconId: beaconId, receiptId: receiptId));
    return super.clearSnapshot(
      kind: kind,
      beaconId: beaconId,
      receiptId: receiptId,
    );
  }
}

/// What the server holds for [_nina] before she has been to Questions: one
/// message Bob posted there.
_RecordingAttention _attentionWithUnreadQuestions() {
  final message = AttentionReceipt(
    id: _questionReceiptId,
    category: 'room',
    kind: 'roomActivityLowPriority',
    priority: 'normal',
    title: 'Bob',
    body: 'New message in Questions',
    actionUrl: '/#/beacon/lobby/$_beaconId',
    createdAt: DateTime.utc(2026, 10, 29, 12),
    collapsedCount: 1,
    presentationKey: 'room_message_posted',
    presentationPayloadJson: jsonEncode({
      'eventType': 'roomMessagePosted',
      'beaconId': _beaconId,
      'coordinationItemId': 'questions-1',
      'actorUserId': 'ubob',
      'actorName': 'Bob',
    }),
    surface: AttentionSurface.myWork,
    beaconId: _beaconId,
    actorUserId: 'ubob',
    targetEntityId: 'message-Bob',
    destinationKind: 'beacon_room_message',
    coordinationItemId: 'questions-1',
  );
  return _RecordingAttention()
    ..myWorkAttentionResult = [
      MyWorkBeaconAttention(
        beaconId: _beaconId,
        unseenCount: 1,
        latestUnseen: message,
      ),
    ];
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 30]) async {
  // Bounded: the chat surface hosts animations that never settle.
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the Questions screen of [_beaconId] as [_nina] through its route.
Future<void> _openQuestions(
  WidgetTester tester, {
  required StubAttentionRepository attention,
}) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);

  final effects = RecordingEffects();
  final profileCubit = RoomBodyHarnessProfileCubit(_nina);
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<PresenceCubit>(presenceCubit)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AttentionCase>(
      buildStubAttentionCase(repository: attention),
    )
    ..registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(
        FakeLobbyPort(viewerId: _nina.id),
        FakeRealtimeSyncPort(),
      ),
    )
    ..registerSingleton<BeaconThreadsCase>(
      roomCubitMakeCase(FakeBeaconThreadsRepository(userId: _nina.id)),
    )
    ..registerSingleton<BeaconFactCardRepository>(
      FakeBeaconFactCardRepository(),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(roomCubitFakePresenceRepository())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());

  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(
          deepLinkBuilder: (_) =>
              DeepLink([BeaconLobbyRoute(beaconId: _beaconId)]),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

void main() {
  group('Opening Questions clears the Questions updates waiting for the viewer',
      () {
    testWidgets('the unread Questions message is cleared once Questions is '
        'on screen', (tester) async {
      final attention = _attentionWithUnreadQuestions();

      await _openQuestions(tester, attention: attention);

      // Questions displayed, so the unread message it holds counts as read.
      // The Request-open capture does not take Questions updates (the server
      // leaves them out of it), so the clear has to name the message itself.
      expect(
        attention.captures.where(
          (c) =>
              c.kind == AttentionClearCaptureKind.explicit &&
              c.receiptId == _questionReceiptId,
        ),
        isNotEmpty,
        reason: 'opening Questions must clear the unread message by its id',
      );
      expect(attention.clearCalls, isNotEmpty);
    });
  });
}
