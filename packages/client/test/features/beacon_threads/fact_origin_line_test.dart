// A copied fact shows a generic origin line under its provenance line
// (plan D6/D7, §6.1): «Brought from another Request» / «…Post», with no
// source title and no names. Tapping it asks BeaconFactCardOrigin about the
// copy: an unavailable source gives «The original isn't available to you»
// and leaves the app where it was; an available one opens the source
// Request with focus_fact. The history of a copy ends with «Earlier history
// lives where this fact came from [Open]», and Open does the same.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

/// Opens the copy's actions sheet the way both hosts do.
void _openActions(BuildContext context, BeaconFactCard fact) => unawaited(
  showFactActionsHostSheet(
    context,
    fact: fact,
    canMutate: false,
    onCorrect:
        ({
          required factCardId,
          required newText,
          attachmentsJson,
        }) async {},
    onRemove: ({required factCardId}) async {},
    onSetVisibility: ({required factCardId, required visibility}) async {},
  ),
);

void main() {
  group('origin line in the fact actions sheet header', () {
    testWidgets('a fact copied from a Request reads exactly «Brought from '
        'another Request»: no source title, no names', (tester) async {
      registerFactRepository(FakeOriginFactCardRepository());
      await pumpOpener(tester, open: (ctx) => _openActions(ctx, copiedFact()));

      // The origin line is only the generic phrase: the pinner (Bob) and the
      // last editor (Carol) stay in the provenance line, and nothing in the
      // header names the source Request.
      final l10n = await L10n.delegate.load(const Locale('en'));
      final header = find
          .ancestor(
            of: find.text(l10n.beaconRoomFactManageSheetTitle),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      expect(originLinesUnder(tester, header), [kOriginFromRequest]);
      for (final text in textsUnder(tester, header)) {
        expect(text, isNot(contains(kSourceBeaconId)));
        expect(text, isNot(contains('Source request')));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fact copied from a Post reads exactly «Brought from '
        'another Post»', (tester) async {
      registerFactRepository(FakeOriginFactCardRepository());
      await pumpOpener(
        tester,
        open: (ctx) => _openActions(ctx, copiedFact(originBeaconKind: 1)),
      );

      expect(find.text(kOriginFromPost), findsOneWidget);
      expect(find.textContaining(kOriginFromRequest), findsNothing);
    });

    testWidgets('a fact that is not a copy shows no origin line', (
      tester,
    ) async {
      registerFactRepository(FakeOriginFactCardRepository());
      await pumpOpener(
        tester,
        open: (ctx) => _openActions(ctx, copiedFact(originBeaconKind: null)),
      );

      expect(find.textContaining('Brought from another'), findsNothing);
    });
  });

  group('tapping the origin line', () {
    testWidgets("an unavailable source shows «The original isn't available "
        'to you» for this copy and the location does not change', (
      tester,
    ) async {
      final repo = FakeOriginFactCardRepository();
      registerFactRepository(repo);
      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => _openActions(ctx, copiedFact()),
      );
      final before = routerLocation(router);
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(kOriginFromRequest));
      await tester.pumpAndSettle();

      expect(repo.originCalls, [
        (beaconId: kCopyBeaconId, factCardId: kCopyFactId),
      ]);
      expect(find.text(kOriginUnavailable, findRichText: true), findsOneWidget);
      expect(routerLocation(router), before);
      expect(find.text(kCopyPageMarker), findsOneWidget);
    });

    testWidgets('an available source opens that Request with focus_fact set '
        'to the source fact', (tester) async {
      registerFactRepository(
        FakeOriginFactCardRepository(originAnswer: availableOrigin()),
      );
      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => _openActions(ctx, copiedFact()),
      );
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(kOriginFromRequest));
      await tester.pumpAndSettle();

      final location = routerLocation(router);
      expect(location.path, '/beacon/view/$kSourceBeaconId');
      expect(location.queryParameters['focus_fact'], kSourceFactId);
      expect(find.text('source-page:$kSourceBeaconId'), findsOneWidget);
      expect(find.text(kOriginUnavailable, findRichText: true), findsNothing);
    });
  });

  group('history footer of a copy', () {
    /// Opens the copy's history the way a reader does: the room's actions
    /// sheet, then «Edit history».
    Future<RootRouter> pumpRoomHistory(
      WidgetTester tester, {
      required BeaconFactCard fact,
      required FakeOriginFactCardRepository repo,
    }) async {
      registerFactRepository(repo);
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      addTearDown(fakeRoom.dispose);
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => unawaited(
          showFactActionsSheet(ctx, cubit: cubit, fact: fact),
        ),
      );
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();
      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.beaconRoomFactCardActionEditHistory));
      await tester.pumpAndSettle();
      expect(find.byType(FactHistorySheet), findsOneWidget);
      return router;
    }

    testWidgets('ends with «Earlier history lives where this fact came from» '
        'below every revision, and Open with an unavailable source shows the '
        'snackbar and stays put', (tester) async {
      final repo = FakeOriginFactCardRepository(historyLength: 2);
      final router = await pumpRoomHistory(
        tester,
        fact: copiedFact(beaconId: kRoomCubitFakeBeaconId),
        repo: repo,
      );
      final before = routerLocation(router);

      expect(find.text(kEarlierHistoryFooter), findsOneWidget);
      expect(find.text(kOpen), findsOneWidget);
      final footerTop = tester.getRect(find.text(kEarlierHistoryFooter)).top;
      for (final seq in [1, 2]) {
        final row = find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains(revisionActor(seq)),
        );
        expect(footerTop, greaterThan(tester.getRect(row).bottom));
      }

      await tester.tap(find.text(kOpen));
      await tester.pumpAndSettle();

      expect(repo.originCalls, [
        (beaconId: kRoomCubitFakeBeaconId, factCardId: kCopyFactId),
      ]);
      expect(find.text(kOriginUnavailable, findRichText: true), findsOneWidget);
      expect(routerLocation(router), before);
    });

    testWidgets('Open with an available source opens it with focus_fact, '
        'like the origin line', (tester) async {
      final router = await pumpRoomHistory(
        tester,
        fact: copiedFact(beaconId: kRoomCubitFakeBeaconId),
        repo: FakeOriginFactCardRepository(
          historyLength: 2,
          originAnswer: availableOrigin(),
        ),
      );

      await tester.tap(find.text(kOpen));
      await tester.pumpAndSettle();

      final location = routerLocation(router);
      expect(location.path, '/beacon/view/$kSourceBeaconId');
      expect(location.queryParameters['focus_fact'], kSourceFactId);
    });

    testWidgets('a fact that is not a copy has no such footer', (
      tester,
    ) async {
      await pumpRoomHistory(
        tester,
        fact: copiedFact(
          originBeaconKind: null,
          beaconId: kRoomCubitFakeBeaconId,
        ),
        repo: FakeOriginFactCardRepository(historyLength: 2),
      );

      expect(find.textContaining('Earlier history'), findsNothing);
      expect(find.text(kOpen), findsNothing);
    });
  });
}
