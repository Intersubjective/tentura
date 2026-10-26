import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_already_pinned_exception.dart';
import 'package:tentura/features/beacon_threads/ui/message/beacon_room_fact_messages.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_fact_composer_sheet.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart' show pumpUntil;

/// #759 review r1 #3 and #4: Pin again reuses a posted-but-unpinned message
/// only while that can still work. A refusal the server stands by, a
/// different fact already on the message, or closing the Add-fact form all
/// make the next pin post its own message instead of failing on the old one
/// forever.
void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bfacts01';

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  BeaconFactCard fact(String id, String text) => BeaconFactCard(
    id: id,
    beaconId: beaconId,
    factText: text,
    visibility: BeaconFactCardVisibilityBits.public,
    pinnedBy: 'Uother',
    createdAt: DateTime.utc(2026),
    status: BeaconFactCardStatusBits.active,
  );

  Future<BeaconViewCubit> loadedCubit(
    FakeBeaconViewFactCardRepository facts,
    FakeBeaconViewRoomRepository room, {
    FakeUiEffectPort? effects,
  }) async {
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon(),
        factCardsRepo: facts,
        roomRepo: room,
      ),
      effects: effects ?? FakeUiEffectPort(),
    );
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    return cubit;
  }

  Future<bool> pin(BeaconViewCubit cubit) => cubit.pinFactFromComposer(
    messageBody: 'QA609 factB',
    factText: 'QA609 factB',
    visibility: BeaconFactCardVisibilityBits.room,
  );

  test('a refusal the server stands by: Pin again posts afresh', () async {
    final facts = FakeBeaconViewFactCardRepository()
      ..pinError = const RemoteApiException('Message not found');
    final room = FakeBeaconViewRoomRepository()..nextMessageId = 'Rserver01';
    final cubit = await loadedCubit(facts, room);
    addTearDown(cubit.close);

    expect(await pin(cubit), isFalse);
    facts.pinError = null;
    room.nextMessageId = 'Rserver02';

    expect(await pin(cubit), isTrue);
    expect(room.createdMessages, hasLength(2));
    expect(facts.pins.single.sourceMessageId, 'Rserver02');
  });

  test(
    'a busy server keeps the posted message for Pin again (guard)',
    () async {
      final facts = FakeBeaconViewFactCardRepository()
        ..pinError = const RemoteApiRetryLaterException(Duration.zero);
      final room = FakeBeaconViewRoomRepository()..nextMessageId = 'Rserver01';
      final cubit = await loadedCubit(facts, room);
      addTearDown(cubit.close);

      expect(await pin(cubit), isFalse);
      facts.pinError = null;
      room.nextMessageId = 'Rserver02';

      expect(await pin(cubit), isTrue);
      expect(room.createdMessages, hasLength(1));
      expect(facts.pins.single.sourceMessageId, 'Rserver01');
    },
  );

  test('a different fact on the posted message is not counted as ours, and '
      'Pin again posts afresh', () async {
    final facts = FakeBeaconViewFactCardRepository(
      cards: [fact('F9', 'pinned by someone else')],
    )..pinError = const BeaconFactAlreadyPinnedException(factCardId: 'F9');
    final room = FakeBeaconViewRoomRepository()..nextMessageId = 'Rserver01';
    final effects = FakeUiEffectPort();
    final cubit = await loadedCubit(facts, room, effects: effects);
    addTearDown(cubit.close);

    expect(await pin(cubit), isFalse);
    expect(
      effects.emitted.whereType<ShowMessage>().last.message,
      isA<BeaconFactPinTakenMessage>(),
    );

    facts.pinError = null;
    room.nextMessageId = 'Rserver02';
    expect(await pin(cubit), isTrue);
    expect(room.createdMessages, hasLength(2));
    expect(facts.pins.single.sourceMessageId, 'Rserver02');
  });

  testWidgets('closing the Add-fact form forgets the posted message', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await GetIt.I.reset();
    addTearDown(GetIt.I.reset);
    GetIt.I
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(
        ClipboardImageRepository(),
      );

    final facts = FakeBeaconViewFactCardRepository()
      ..pinError = StateError('pin failed');
    final room = FakeBeaconViewRoomRepository()..nextMessageId = 'Rserver01';
    final cubit = (await tester.runAsync(() async {
      final c = await loadedCubit(facts, room);
      // A failed pin from an earlier form: the message is kept for reuse.
      expect(await pin(c), isFalse);
      return c;
    }))!;
    addTearDown(cubit.close);

    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    final closed = showBeaconFactComposerSheet(pageContext, cubit: cubit);
    await tester.pumpAndSettle();
    final title = find.text(l10n.beaconFactsComposerTitle);
    expect(title, findsOneWidget);
    Navigator.of(tester.element(title)).pop();
    await tester.pumpAndSettle();
    expect(await closed, isFalse);

    facts.pinError = null;
    room.nextMessageId = 'Rserver02';
    final ok = await tester.runAsync(() => pin(cubit));

    expect(ok, isTrue);
    expect(room.createdMessages, hasLength(2));
    expect(facts.pins.single.sourceMessageId, 'Rserver02');
  });
}
