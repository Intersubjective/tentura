// #481: the Add-fact form (beacon_fact_composer_sheet.dart) named the room
// thread "General" in its hint and silently ignored Pin with an empty field.
//
// Fails to compile until the l10n key `beaconFactsComposerEmptyError`
// exists (en + ru); then fails until Pin on an empty form shows it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Author');
const _beaconId = 'B481';

Beacon _beacon() => Beacon(
  id: _beaconId,
  title: 'Facts beacon',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: _author,
);

/// Opens the pinned-facts sheet as the author (empty room) and taps
/// "Add fact" to bring up the composer, as in
/// beacon_pinned_facts_sheet_test.dart.
Future<FakeBeaconViewFactCardRepository> _openComposer(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final factsRepo = FakeBeaconViewFactCardRepository();
  final cubit = (await tester.runAsync(() async {
    final c = BeaconViewCubit(
      id: _beaconId,
      myProfile: _author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => _beacon(),
        factCardsRepo: factsRepo,
        roomRepo: FakeBeaconViewRoomRepository(),
      ),
      effects: FakeUiEffectPort(),
    );
    await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
    return c;
  }))!;
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
              onPressed: () => showBeaconPinnedFactsSheet(ctx, cubit: cubit),
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
  await tester.tap(find.byKey(TestIds.key(TestIds.beaconFactsAdd)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return factsRepo;
}

void main() {
  group('#481 Add-fact form', () {
    testWidgets('Pin with an empty field says what is missing', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final factsRepo = await _openComposer(tester);
      expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
      expect(
        find.text(l10n.beaconFactsComposerEmptyError),
        findsNothing,
        reason: 'no error before the user has tried to pin',
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.beaconFactsComposerSubmit)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(l10n.beaconFactsComposerEmptyError),
        findsOneWidget,
        reason: 'Pin on an empty form must not silently do nothing',
      );
      expect(
        find.text(l10n.beaconFactsComposerTitle),
        findsOneWidget,
        reason: 'the form stays open',
      );
      expect(factsRepo.pins, isEmpty, reason: 'nothing may be pinned');

      await tester.enterText(
        find.byType(TextField),
        'Door code 4711',
      );
      await tester.pump();

      expect(
        find.text(l10n.beaconFactsComposerEmptyError),
        findsNothing,
        reason: 'the error clears once there is text',
      );

      // The error is not a permanent block: with text, Pin pins.
      await tester.tap(
        find.byKey(TestIds.key(TestIds.beaconFactsComposerSubmit)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        factsRepo.pins,
        hasLength(1),
        reason:
            'after the empty-pin error, typing text and tapping Pin '
            'must pin the fact',
      );
      expect(factsRepo.pins.single.factText, contains('Door code 4711'));
      expect(
        find.text(l10n.beaconFactsComposerEmptyError),
        findsNothing,
      );
    });

    testWidgets('the hint does not name the thread General', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _openComposer(tester);

      final hint = l10n.beaconFactsComposerPostsToDiscussion;
      expect(find.text(hint), findsOneWidget);
      expect(hint, isNot(contains('General')));
      expect(
        hint.toLowerCase(),
        anyOf(contains('discussion'), contains('chat')),
      );
    });

    test('ru copy: no «Общее», empty-pin error translated', () async {
      final en = await L10n.delegate.load(const Locale('en'));
      final ru = await L10n.delegate.load(const Locale('ru'));

      final hint = ru.beaconFactsComposerPostsToDiscussion;
      expect(hint, isNot(contains('Общее')));
      expect(hint.toLowerCase(), anyOf(contains('обсужд'), contains('чат')));

      expect(ru.beaconFactsComposerEmptyError.trim(), isNotEmpty);
      expect(
        ru.beaconFactsComposerEmptyError,
        isNot(en.beaconFactsComposerEmptyError),
      );
    });
  });
}
