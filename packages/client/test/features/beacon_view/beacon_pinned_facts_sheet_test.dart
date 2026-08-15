import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bsheet01';
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  BeaconFactCard fact({
    required String id,
    required DateTime createdAt,
    String pinnedBy = 'other',
  }) =>
      BeaconFactCard(
        id: id,
        beaconId: beaconId,
        factText: 'Fact $id',
        visibility: BeaconFactCardVisibilityBits.public,
        pinnedBy: pinnedBy,
        createdAt: createdAt,
        status: BeaconFactCardStatusBits.active,
      );

  Future<BeaconViewCubit> loadedCubit({
    required List<BeaconFactCard> cards,
    DateTime? baselineFactsAt,
    Profile? profile,
  }) async {
    final me = profile ?? myProfile;
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
      factCardsRepo: FakeBeaconViewFactCardRepository(cards: cards),
    );
    if (baselineFactsAt != null) {
      case_.baselinePinnedFactsIfNeeded(
        beaconId: beaconId,
        userId: me.id,
        facts: [fact(id: 'baseline', createdAt: baselineFactsAt)],
      );
    }
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: me,
      beaconViewCase: case_,
      coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
      effects: FakeUiEffectPort(),
    );
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    return cubit;
  }

  testWidgets('sheet uses passed cubit without Provider (My Work pane)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = (await tester.runAsync(
      () => loadedCubit(
        cards: [fact(id: 'f1', createdAt: t0)],
      ),
    ))!;
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showBeaconPinnedFactsSheet(
                  ctx,
                  cubit: cubit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
    expect(find.text('Fact f1'), findsOneWidget);
    expect(find.byType(BeaconPinnedFactCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet marks seen on close using max fact timestamp', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = (await tester.runAsync(
      () => loadedCubit(
        cards: [
          fact(id: 'old', createdAt: t0),
          fact(id: 'new', createdAt: t1),
        ],
        baselineFactsAt: t0,
      ),
    ))!;
    addTearDown(cubit.close);

    expect(cubit.state.pinnedFactsSeenAt, t0);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showBeaconPinnedFactsSheet(
                  ctx,
                  cubit: cubit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);

    Navigator.of(tester.element(find.text(l10n.beaconFactsSheetTitle))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cubit.state.pinnedFactsSeenAt, t1);
  });

  Widget sheetHost(BeaconViewCubit cubit) {
    return MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showBeaconPinnedFactsSheet(
                ctx,
                cubit: cubit,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Add fact is hidden without coordination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = (await tester.runAsync(
      () => loadedCubit(cards: [fact(id: 'f1', createdAt: t0)]),
    ))!;
    addTearDown(cubit.close);

    await tester.pumpWidget(sheetHost(cubit));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsAddFact), findsNothing);
  });

  testWidgets('Add fact opens composer for the author', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const author = Profile(id: 'Uauthor', displayName: 'Author');
    final cubit = (await tester.runAsync(
      () => loadedCubit(
        cards: [fact(id: 'f1', createdAt: t0)],
        profile: author,
      ),
    ))!;
    addTearDown(cubit.close);

    await tester.pumpWidget(sheetHost(cubit));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsAddFact), findsOneWidget);

    await tester.tap(find.byKey(TestIds.key(TestIds.beaconFactsAdd)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
    expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
  });

  testWidgets('new fact appears without closing the facts sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const author = Profile(id: 'Uauthor', displayName: 'Author');
    final factsRepo = FakeBeaconViewFactCardRepository(
      cards: [fact(id: 'f1', createdAt: t0)],
    );
    final cubit = (await tester.runAsync(() async {
      final case_ = buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon(),
        factCardsRepo: factsRepo,
        roomRepo: FakeBeaconViewRoomRepository(),
      );
      final c = BeaconViewCubit(
        id: beaconId,
        myProfile: author,
        beaconViewCase: case_,
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
      return c;
    }))!;
    addTearDown(cubit.close);

    await tester.pumpWidget(sheetHost(cubit));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    factsRepo.cards = [
      fact(id: 'f1', createdAt: t0),
      fact(id: 'f2', createdAt: t1, pinnedBy: author.id),
    ];
    await tester.runAsync(
      () => cubit.pinFactFromComposer(
        messageBody: 'Fact f2',
        factText: 'Fact f2',
        visibility: BeaconFactCardVisibilityBits.public,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
    expect(find.text('Fact f2'), findsOneWidget);
  });
}
