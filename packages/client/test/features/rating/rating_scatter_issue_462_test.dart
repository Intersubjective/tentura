// GitHub #462 — Rating > Scatter view: everyone with "rank to you" = 0 is
// stacked at the left edge, so ~20 avatars and names overlap into an
// illegible blob, and nothing names the axes (only the faint quadrant words).
//
// Spec: overlapping points are spread apart or clustered with a "+N" count,
// so no two visible name labels sit on top of each other and every person is
// still accounted for; the plot carries axis titles reusing the Rating
// column words: x (their rank of you, rScore) = "Rank to you",
// y (your rank of them, score) = "Rank from you".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/rating/ui/bloc/rating_cubit.dart';
import 'package:tentura/features/rating/ui/widget/rating_scatter_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _RatingCubitStub extends Mock implements RatingCubit {
  @override
  RatingState get state => const RatingState();

  @override
  Stream<RatingState> get stream => const Stream<RatingState>.empty();
}

class _ProfileCubitStub extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

/// The issue's repro: a new user, twenty strangers who rank them 0 back and
/// whom they rank only slightly (a handful of nearly equal small scores).
final _stacked = [
  for (var i = 0; i < 20; i++)
    Profile(
      id: 'u-stack-$i',
      displayName: 'Stranger ${i.toString().padLeft(2, '0')}',
      score: 4 + (i % 4) * 0.5,
    ),
];

/// Guard: four people far apart (one per quadrant) never need clustering.
const _spread = [
  Profile(id: 'u-a', displayName: 'Alice Idol', score: 90, rScore: 10),
  Profile(id: 'u-b', displayName: 'Bob Friend', score: 90, rScore: 90),
  Profile(id: 'u-c', displayName: 'Cara Acq', score: 10, rScore: 10),
  Profile(id: 'u-d', displayName: 'Dan Fan', score: 10, rScore: 90),
];

final _countPattern = RegExp(r'^\+\s?(\d+)\b');

Future<void> _pumpScatter(
  WidgetTester tester,
  List<Profile> profiles, {
  Locale locale = const Locale('en'),
}) async {
  // The issue's desktop viewport.
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
          BlocProvider<RatingCubit>.value(value: _RatingCubitStub()),
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

/// Sum of every "+N" cluster count shown in the plot.
int _clusterCountTotal(WidgetTester tester) {
  var total = 0;
  for (final t in tester.widgetList<Text>(_inScatter(find.byType(Text)))) {
    final s = (t.data ?? t.textSpan?.toPlainText() ?? '').trim();
    final m = _countPattern.firstMatch(s);
    if (m != null) total += int.parse(m.group(1)!);
  }
  return total;
}

/// On-screen rects of the name labels that are actually shown.
Map<String, Rect> _visibleNameRects(
  WidgetTester tester,
  List<Profile> profiles,
) => {
  for (final p in profiles)
    if (_inScatter(find.text(p.displayName)).evaluate().isNotEmpty)
      p.displayName: tester.getRect(_inScatter(find.text(p.displayName)).first),
};

double _overlapShare(Rect a, Rect b) {
  final i = a.intersect(b);
  if (i.width <= 0 || i.height <= 0) return 0;
  final smaller = [
    a.width * a.height,
    b.width * b.height,
  ].reduce((x, y) => x < y ? x : y);
  return smaller <= 0 ? 0 : (i.width * i.height) / smaller;
}

/// The title widget for an axis: a Text whose words contain [label].
Finder _axisTitle(String label) => _inScatter(find.textContaining(label));

void main() {
  group('#462 Scatter overlapping points', () {
    testWidgets('stacked people at rank-to-you 0 do not overlap names', (
      tester,
    ) async {
      await _pumpScatter(tester, _stacked);

      final rects = _visibleNameRects(tester, _stacked);
      final names = rects.keys.toList();
      final collisions = <String>[];
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          if (_overlapShare(rects[names[i]]!, rects[names[j]]!) > 0.3) {
            collisions.add('${names[i]} / ${names[j]}');
          }
        }
      }
      expect(
        collisions,
        isEmpty,
        reason: 'visible name labels must not sit on top of each other',
      );
    });

    testWidgets(
      'guard: every stacked person is shown or counted in a +N cluster',
      (
        tester,
      ) async {
        await _pumpScatter(tester, _stacked);

        final shown = _visibleNameRects(tester, _stacked).length;
        final counted = _clusterCountTotal(tester);
        // Nobody silently disappears, and nobody is counted twice.
        expect(shown + counted, _stacked.length);
        // Not an empty plot: someone stays visible by name.
        expect(shown, greaterThan(0));
      },
    );

    testWidgets('guard: well separated people all keep their names', (
      tester,
    ) async {
      await _pumpScatter(tester, _spread);

      for (final p in _spread) {
        expect(_inScatter(find.text(p.displayName)), findsOneWidget);
      }
      expect(_clusterCountTotal(tester), 0);
    });
  });

  group('#462 Scatter axis titles', () {
    testWidgets('both axes are titled with the Rating column words', (
      tester,
    ) async {
      await _pumpScatter(tester, _spread);

      final l10n = lookupL10n(const Locale('en'));
      expect(_axisTitle(l10n.rankToYou), findsOneWidget);
      expect(_axisTitle(l10n.rankFromYou), findsOneWidget);
    });

    testWidgets('x title sits below the plot centre, y title left of it', (
      tester,
    ) async {
      await _pumpScatter(tester, _spread);

      final l10n = lookupL10n(const Locale('en'));
      final view = tester.getRect(find.byType(RatingScatterView));
      // x axis = their rank of you (rScore): horizontal, along the bottom.
      final x = tester.getRect(_axisTitle(l10n.rankToYou));
      // y axis = your rank of them (score): along the left edge.
      final y = tester.getRect(_axisTitle(l10n.rankFromYou));
      expect(x.center.dy, greaterThan(view.center.dy));
      expect(y.center.dx, lessThan(view.center.dx));
      // Not swapped: the x title is lower than the y title is.
      expect(x.center.dy, greaterThan(y.center.dy));
      // Both on screen.
      expect(view.inflate(1).contains(x.center), isTrue);
      expect(view.inflate(1).contains(y.center), isTrue);
    });

    testWidgets('Russian: axes are titled too', (tester) async {
      await _pumpScatter(tester, _spread, locale: const Locale('ru'));

      final l10n = lookupL10n(const Locale('ru'));
      expect(_axisTitle(l10n.rankToYou), findsOneWidget);
      expect(_axisTitle(l10n.rankFromYou), findsOneWidget);
    });
  });
}
