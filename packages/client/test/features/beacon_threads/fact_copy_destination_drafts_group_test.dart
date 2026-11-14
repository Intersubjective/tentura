// The «Use in another Request» destination picker lists the person's own
// drafts apart from the open Requests: a «Your drafts» group header, with the
// draft rows under it (fact continuity plan §6.2). A tap on a draft row copies
// the fact into that draft like any other destination.
//
// The picker is reached the way a person reaches it: the room's fact actions
// sheet and a tap on the «Use in another Request» tile. Copy and destinations
// go through the real BeaconThreadsCase; the repository is a fake.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _factId = 'Fkey00000001';
const _draftsHeader = 'Your drafts';
const _draftTitle = 'Tool shed rota';

BeaconFactCopyDestination _dest(
  String id,
  String title, {
  required bool isDraft,
}) => (id: id, kind: 0, title: title, isDraft: isDraft, expiresAt: null);

class _CopyRepo extends FakeOriginFactCardRepository {
  _CopyRepo({required this.rows});

  final List<BeaconFactCopyDestination> rows;
  final copyCalls = <({String sourceFactCardId, String destinationBeaconId})>[];

  @override
  Future<List<BeaconFactCopyDestination>> destinations({
    required String sourceFactCardId,
  }) async => rows;

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    copyCalls.add((
      sourceFactCardId: sourceFactCardId,
      destinationBeaconId: destinationBeaconId,
    ));
    return (factCardId: 'Fnew00000001', outcome: BeaconFactCopyOutcome.created);
  }
}

BeaconFactCard _fact() => copiedFact(
  originBeaconKind: null,
  id: _factId,
  beaconId: kRoomCubitFakeBeaconId,
  factText: 'Key is under the mat',
);

Future<void> _openPicker(
  WidgetTester tester,
  BeaconFactCardRepository repo, {
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<Logger>()) {
    getIt.registerSingleton<Logger>(Logger('test'));
    addTearDown(() {
      // ignore: discarded_futures -- best-effort unregister.
      getIt.unregister<Logger>();
    });
  }
  registerFactRepository(repo);
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);
  final cubit = roomCubitForTest(
    fakeRoom,
    beaconRoomCase: GetIt.instance<BeaconThreadsCase>(),
  );
  addTearDown(cubit.close);
  await awaitRoomCubitLoad(cubit);
  await pumpOpener(
    tester,
    locale: locale,
    size: size,
    open: (ctx) => unawaited(
      showFactActionsSheet(ctx, cubit: cubit, fact: _fact()),
    ),
  );
  await tester.tap(
    find.text(
      locale.languageCode == 'ru'
          ? russianFor(kUseInAnotherRequest)
          : kUseInAnotherRequest,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('destination picker «Your drafts» group', () {
    testWidgets('lists open Requests first, then a «Your drafts» header with '
        'the draft rows under it', (tester) async {
      await _openPicker(
        tester,
        _CopyRepo(
          rows: [
            _dest('Bgarden0001', 'Garden day', isDraft: false),
            _dest('Bdraft00001', _draftTitle, isDraft: true),
          ],
        ),
      );

      expect(find.text(_draftsHeader), findsOneWidget);
      final open = tester.getTopLeft(find.text('Garden day')).dy;
      final header = tester.getTopLeft(find.text(_draftsHeader)).dy;
      final draft = tester.getTopLeft(find.text(_draftTitle)).dy;
      expect(open, lessThan(header), reason: 'open Request is above the group');
      expect(header, lessThan(draft), reason: 'the draft is under its header');
    });

    testWidgets('every open Request stays above the header, the drafts below '
        'it', (tester) async {
      await _openPicker(
        tester,
        _CopyRepo(
          rows: [
            _dest('Bgarden0001', 'Garden day', isDraft: false),
            _dest('Bdraft00001', _draftTitle, isDraft: true),
            _dest('Bshed000001', 'Tool shed', isDraft: false),
            _dest('Bdraft00002', 'Roof plan draft', isDraft: true),
          ],
        ),
      );

      final header = tester.getTopLeft(find.text(_draftsHeader)).dy;
      for (final open in ['Garden day', 'Tool shed']) {
        expect(tester.getTopLeft(find.text(open)).dy, lessThan(header));
      }
      for (final draft in [_draftTitle, 'Roof plan draft']) {
        expect(tester.getTopLeft(find.text(draft)).dy, greaterThan(header));
      }
    });

    testWidgets('without any draft row there is no «Your drafts» header', (
      tester,
    ) async {
      await _openPicker(
        tester,
        _CopyRepo(
          rows: [
            _dest('Bgarden0001', 'Garden day', isDraft: false),
            _dest('Bshed000001', 'Tool shed', isDraft: false),
          ],
        ),
      );

      expect(find.text('Garden day'), findsOneWidget);
      expect(find.text(_draftsHeader), findsNothing);
    });

    testWidgets('tapping a draft row copies into that draft, closes the '
        'picker and says «Copied to Tool shed rota»', (tester) async {
      final repo = _CopyRepo(
        rows: [
          _dest('Bgarden0001', 'Garden day', isDraft: false),
          _dest('Bdraft00001', _draftTitle, isDraft: true),
        ],
      );
      await _openPicker(tester, repo);
      expect(find.text(_draftsHeader), findsOneWidget);

      await tester.tap(find.text(_draftTitle));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [
        (sourceFactCardId: _factId, destinationBeaconId: 'Bdraft00001'),
      ]);
      expect(find.text(_draftsHeader), findsNothing, reason: 'picker closed');
      expect(
        find.text('Copied to $_draftTitle', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('«Your drafts» has a Russian entry and shows Russian under '
        'the ru locale at 375x667 without overflow', (tester) async {
      final longDraft =
          'Очень длинное название черновика про сад и инструменты ' * 3;
      final ruHeader = russianFor(_draftsHeader);
      expect(hasCyrillic(ruHeader), isTrue);

      await _openPicker(
        tester,
        _CopyRepo(
          rows: [
            _dest('Bgarden0001', 'Garden day', isDraft: false),
            _dest('Bdraft00001', longDraft, isDraft: true),
          ],
        ),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      expect(find.text(ruHeader), findsOneWidget);
      expect(find.text(_draftsHeader), findsNothing);
      expect(find.text(longDraft), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(longDraft)).dy,
        greaterThan(tester.getTopLeft(find.text(ruHeader)).dy),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
