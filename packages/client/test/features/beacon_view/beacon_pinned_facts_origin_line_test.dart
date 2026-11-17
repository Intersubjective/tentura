// Request detail facts sheet: each copied fact's row shows the generic
// origin line («Brought from another Request» / «…Post», plan D6/§6.1);
// facts that are not copies show none, and tapping the line runs the same
// origin flow as in the actions sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';

import '../../support/fact_sheet_feedback.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fact_origin_test_support.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart' show pumpUntil;

const _beaconId = kCopyBeaconId;

Future<BeaconViewCubit> _loadedCubit(
  WidgetTester tester,
  List<BeaconFactCard> cards,
) async {
  final beacon = Beacon(
    id: _beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );
  final cubit = (await tester.runAsync(() async {
    final c = BeaconViewCubit(
      id: _beaconId,
      myProfile: const Profile(id: 'Uviewer', displayName: 'Viewer'),
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => beacon,
        factCardsRepo: FakeBeaconViewFactCardRepository(cards: cards),
      ),
      effects: FakeUiEffectPort(),
    );
    await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
    return c;
  }))!;
  addTearDown(cubit.close);
  return cubit;
}

Finder _row(String factText) => find.ancestor(
  of: find.textContaining(factText),
  matching: find.byType(BeaconPinnedFactCard),
);

void main() {
  group('phone feedback from pinned facts', () {
    for (final language in ['en', 'ru']) {
      testWidgets(
        'an unavailable origin is visible and keeps the current Request in $language',
        (tester) async {
          registerFactRepository(FakeOriginFactCardRepository());
          final cubit = await _loadedCubit(tester, [copiedFact()]);
          final router = await pumpOriginRouter(
            tester,
            locale: Locale(language),
            size: kPhoneSurface,
            openCopy: (ctx) =>
                unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
          );
          final before = routerLocation(router);
          await tester.tap(find.text('open-copy'));
          await tester.pumpAndSettle();
          final l10n = await L10n.delegate.load(Locale(language));
          await tester.tap(find.text(l10n.beaconRoomFactOriginFromRequest));
          await tester.pumpAndSettle();
          expect(routerLocation(router), before);
          expectPhoneFeedback(
            tester,
            language == 'en'
                ? "The original isn't available to you"
                : 'Оригинал вам недоступен',
          );
        },
      );
    }
    testWidgets('an origin lookup failure is visible above pinned facts', (
      tester,
    ) async {
      registerPhoneFeedbackLogger();
      registerFactRepository(_OriginFailureRepo());
      final cubit = await _loadedCubit(tester, [copiedFact()]);
      await pumpOpener(
        tester,
        size: kPhoneSurface,
        open: (ctx) => unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
      );
      await tester.tap(find.text(kOriginFromRequest));
      await tester.pumpAndSettle();
      final snack = find.byType(SnackBar);
      expect(
        snack,
        findsOneWidget,
        reason: 'lookup failure must produce an error snackbar',
      );
      expect(
        snack.hitTestable(),
        findsOneWidget,
        reason: 'the error snackbar must be above the modal barrier',
      );
      final rect = tester.getRect(snack);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(kPhoneSurface.height));
    });
  });

  testWidgets(
    "each copied fact's row reads only «Brought from another Request» or "
    '«…Post» (no names, no source title); a fact that is not a copy has no '
    'origin line',
    (tester) async {
      registerFactRepository(FakeOriginFactCardRepository());
      final fromRequest = copiedFact(id: 'f-req').copyWith(factText: 'From R');
      final fromPost = copiedFact(
        id: 'f-post',
        originBeaconKind: 1,
      ).copyWith(factText: 'From P');
      final own = copiedFact(
        id: 'f-own',
        originBeaconKind: null,
      ).copyWith(factText: 'Own fact');
      final cubit = await _loadedCubit(tester, [fromRequest, fromPost, own]);

      await pumpOpener(
        tester,
        open: (ctx) => unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
      );

      expect(find.byType(BeaconPinnedFactCard), findsNWidgets(3));
      // Each copy's origin line is only the generic phrase: no pinner (Bob),
      // no editor (Carol), no source Request title.
      expect(originLinesUnder(tester, _row('From R')), [kOriginFromRequest]);
      expect(originLinesUnder(tester, _row('From P')), [kOriginFromPost]);
      expect(originLinesUnder(tester, _row('Own fact')), isEmpty);
      for (final row in ['From R', 'From P']) {
        for (final text in textsUnder(tester, _row(row))) {
          expect(text, isNot(contains(kSourceBeaconId)));
          expect(text, isNot(contains('Source request')));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("tapping a row's origin line with an unavailable source shows "
      'the snackbar and the location does not change', (tester) async {
    final repo = FakeOriginFactCardRepository();
    registerFactRepository(repo);
    final cubit = await _loadedCubit(tester, [copiedFact()]);
    final router = await pumpOriginRouter(
      tester,
      openCopy: (ctx) =>
          unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
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
  });

  testWidgets("tapping a row's origin line with an available source opens "
      'that Request with focus_fact', (tester) async {
    registerFactRepository(
      FakeOriginFactCardRepository(originAnswer: availableOrigin()),
    );
    final cubit = await _loadedCubit(tester, [copiedFact()]);
    final router = await pumpOriginRouter(
      tester,
      openCopy: (ctx) =>
          unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
    );
    await tester.tap(find.text('open-copy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(kOriginFromRequest));
    await tester.pumpAndSettle();

    final location = routerLocation(router);
    expect(location.path, '/beacon/view/$kSourceBeaconId');
    expect(location.queryParameters['focus_fact'], kSourceFactId);
  });

  testWidgets('a copied fact row fits a 375 px wide sheet', (tester) async {
    registerFactRepository(FakeOriginFactCardRepository());
    final cubit = await _loadedCubit(tester, [copiedFact()]);
    await pumpOpener(
      tester,
      size: const Size(375, 667),
      open: (ctx) => unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
    );
    expect(find.textContaining(kOriginFromRequest), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _OriginFailureRepo extends FakeOriginFactCardRepository {
  @override
  Future<BeaconFactOrigin> origin({
    required String beaconId,
    required String factCardId,
  }) async => throw StateError('offline');
}
