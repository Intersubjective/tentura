// GitHub #615 (follow-up of #462), decision A — Rating > Scatter view: the
// "+N" cluster chip could only be expanded by zooming; there was no list of
// the people folded into it.
//
// Spec: tapping the "+N" chip opens a sheet titled with how many people are
// there, listing every member of the cluster (the lead and everyone hidden
// behind the chip) with avatar, name and both scores. Tapping a person opens
// their profile (and closes the sheet). The old zoom-into-cluster stays one
// tap away inside the sheet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/rating/ui/bloc/rating_cubit.dart';
import 'package:tentura/features/rating/ui/widget/rating_scatter_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _RatingCubitStub extends Mock implements RatingCubit {
  final opened = <String>[];

  @override
  RatingState get state => const RatingState();

  @override
  Stream<RatingState> get stream => const Stream<RatingState>.empty();

  @override
  void showProfile(String id) => opened.add(id);
}

class _ProfileCubitStub extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

/// The #462 repro: twenty strangers who rank you 0, nearly equal scores.
final _stacked = [
  for (var i = 0; i < 20; i++)
    Profile(
      id: 'u-stack-$i',
      displayName: 'Stranger ${i.toString().padLeft(2, '0')}',
      score: 4 + (i % 4) * 0.5,
    ),
];

/// Guard: four people far apart never form a cluster, so there is no chip.
const _spread = [
  Profile(id: 'u-a', displayName: 'Alice Idol', score: 90, rScore: 10),
  Profile(id: 'u-b', displayName: 'Bob Friend', score: 90, rScore: 90),
  Profile(id: 'u-c', displayName: 'Cara Acq', score: 10, rScore: 10),
  Profile(id: 'u-d', displayName: 'Dan Fan', score: 10, rScore: 90),
];

final _countPattern = RegExp(r'^\+\s?(\d+)$');

Future<void> _pump(
  WidgetTester tester,
  List<Profile> profiles,
  _RatingCubitStub rating, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<RatingCubit>.value(value: rating),
          BlocProvider<ProfileCubit>.value(value: _ProfileCubitStub()),
        ],
        child: Scaffold(body: RatingScatterView(profiles: profiles)),
      ),
    ),
  );
  await tester.pump();
}

Finder _inScatter(Finder matching) =>
    find.descendant(of: find.byType(RatingScatterView), matching: matching);

Finder _inSheet(Finder matching) => find.descendant(
  of: find.byType(BottomSheet),
  matching: matching,
  skipOffstage: false,
);

/// The biggest "+N" chip in the plot: its text and N.
MapEntry<String, int> _biggestChip(WidgetTester tester) {
  final chips = <String, int>{};
  for (final t in tester.widgetList<Text>(_inScatter(find.byType(Text)))) {
    final s = (t.data ?? t.textSpan?.toPlainText() ?? '').trim();
    final m = _countPattern.firstMatch(s);
    if (m != null) chips[s] = int.parse(m.group(1)!);
  }
  expect(chips, isNotEmpty, reason: 'the stacked repro shows a +N chip');
  return chips.entries.reduce((a, b) => a.value >= b.value ? a : b);
}

/// Members of [profiles] listed by name in the open sheet.
List<Profile> _listed(List<Profile> profiles) => [
  for (final p in profiles)
    if (_inSheet(find.text(p.displayName)).evaluate().isNotEmpty) p,
];

void main() {
  group('#615 the +N chip lists the people in the cluster', () {
    testWidgets('no chip and no sheet when nobody overlaps (guard)', (
      tester,
    ) async {
      await _pump(tester, _spread, _RatingCubitStub());
      for (final p in _spread) {
        expect(_inScatter(find.text(p.displayName)), findsOneWidget);
      }
      expect(_inScatter(find.textContaining(_countPattern)), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });

    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'tapping the chip opens a titled list of everyone ($locale)',
        (
          tester,
        ) async {
          final rating = _RatingCubitStub();
          await _pump(tester, _stacked, rating, locale: locale);
          final chip = _biggestChip(tester);

          await tester.tap(_inScatter(find.text(chip.key)).first);
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsOneWidget);
          final l10n = lookupL10n(locale);
          final members = chip.value + 1; // the lead + everyone behind the chip
          expect(
            _inSheet(find.text(l10n.ratingScatterClusterSheetTitle(members))),
            findsOneWidget,
          );
          final listed = _listed(_stacked);
          expect(
            listed,
            hasLength(members),
            reason: 'the lead and all ${chip.value} hidden people are listed',
          );
          // Each row shows an avatar and both scores.
          expect(
            _inSheet(find.byType(TenturaAvatar)),
            findsNWidgets(members),
          );
          for (final p in listed) {
            expect(
              _inSheet(
                find.text(
                  l10n.ratingScatterClusterMemberScores(
                    p.score.toStringAsFixed(0),
                    p.rScore.toStringAsFixed(0),
                  ),
                ),
              ),
              findsWidgets,
            );
          }
          expect(
            rating.opened,
            isEmpty,
            reason: 'the chip lists the cluster; it does not open the lead',
          );
        },
      );
    }

    testWidgets('tapping a listed person opens their profile', (tester) async {
      final rating = _RatingCubitStub();
      await _pump(tester, _stacked, rating);
      final chip = _biggestChip(tester);
      await tester.tap(_inScatter(find.text(chip.key)).first);
      await tester.pumpAndSettle();

      final listed = _listed(_stacked);
      expect(listed, hasLength(greaterThan(1)));
      // A person who was hidden behind the chip (not the visible lead).
      final hidden = listed.firstWhere(
        (p) => _inScatter(find.text(p.displayName)).evaluate().isEmpty,
      );
      final row = _inSheet(find.text(hidden.displayName));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(rating.opened, [hidden.id]);
      expect(find.byType(BottomSheet), findsNothing, reason: 'sheet closes');
    });
  });

  test('#615 sheet strings exist in en and ru', () {
    final en = lookupL10n(const Locale('en'));
    final ru = lookupL10n(const Locale('ru'));
    expect(en.ratingScatterClusterSheetTitle(17), contains('17'));
    expect(ru.ratingScatterClusterSheetTitle(17), contains('17'));
    expect(
      ru.ratingScatterClusterSheetTitle(5),
      isNot(en.ratingScatterClusterSheetTitle(5)),
    );
    expect(
      en.ratingScatterClusterSheetTitle(1),
      isNot(en.ratingScatterClusterSheetTitle(17).replaceAll('17', '1')),
    );
    expect(en.ratingScatterClusterMemberScores('5', '0'), contains('5'));
    expect(ru.ratingScatterClusterMemberScores('5', '0'), contains('5'));
    expect(
      ru.ratingScatterClusterMemberScores('5', '0'),
      isNot(en.ratingScatterClusterMemberScores('5', '0')),
    );
    expect(ru.ratingScatterClusterZoomIn, isNot(en.ratingScatterClusterZoomIn));
  });
}
