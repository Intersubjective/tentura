// GitHub #462 — owner review of PR #614 ("Should fix" 3–5).
//
// (3) Clustering must not rerun on every pan. A pure translation of the
//     plot's TransformationController keeps the cluster result; only a
//     scale change (while zoomed in, scale > 1) or new profiles / a new self
//     id recompute it. At scale <= 1 it is computed once per profiles/myId.
//     Observed through `RatingScatterView.debugClusterComputations`, a
//     @visibleForTesting counter bumped once per clustering pass.
// (4) The "+N" chip reads to a screen reader as "N more people here"
//     (l10n `ratingScatterClusterMore`, ICU plural, en + ru), and tapping it
//     zooms into that cluster so its members split apart, instead of only
//     opening the lead's profile.
// (5) The y-axis title ("Rank from you") does not sit on top of the avatars
//     in the rank-to-you = 0 column, also on a phone-width viewport.

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

/// The issue's repro: twenty strangers who rank you 0, nearly equal scores.
final _stacked = [
  for (var i = 0; i < 20; i++)
    Profile(
      id: 'u-stack-$i',
      displayName: 'Stranger ${i.toString().padLeft(2, '0')}',
      score: 4 + (i % 4) * 0.5,
    ),
];

/// Everyone ranks you 0, your ranks of them run the full height (0..100),
/// so the rank-to-you = 0 column covers the middle of the left edge where
/// the y-axis title sits.
final _leftColumn = [
  for (var i = 0; i <= 10; i++)
    Profile(id: 'u-col-$i', displayName: 'Column $i', score: i * 10.0),
];

final _countPattern = RegExp(r'^\+\s?(\d+)\b');

Widget _host(
  List<Profile> profiles,
  _RatingCubitStub rating,
  _ProfileCubitStub profile, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: MultiBlocProvider(
    providers: [
      BlocProvider<RatingCubit>.value(value: rating),
      BlocProvider<ProfileCubit>.value(value: profile),
    ],
    child: Scaffold(body: RatingScatterView(profiles: profiles)),
  ),
);

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _inScatter(Finder matching) =>
    find.descendant(of: find.byType(RatingScatterView), matching: matching);

TransformationController _controller(WidgetTester tester) => tester
    .widget<InteractiveViewer>(_inScatter(find.byType(InteractiveViewer)))
    .transformationController!;

Matrix4 _scaleAt(double scale, {double dx = 0, double dy = 0}) =>
    Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(dx, dy, 0);

/// "+N" chips shown in the plot: text -> N.
Map<String, int> _chips(WidgetTester tester) {
  final chips = <String, int>{};
  for (final t in tester.widgetList<Text>(_inScatter(find.byType(Text)))) {
    final s = (t.data ?? t.textSpan?.toPlainText() ?? '').trim();
    final m = _countPattern.firstMatch(s);
    if (m != null) chips[s] = int.parse(m.group(1)!);
  }
  return chips;
}

/// Names of [profiles] whose label is shown with its centre inside [view].
Set<String> _namesInView(
  WidgetTester tester,
  List<Profile> profiles,
  Rect view,
) => {
  for (final p in profiles)
    if (_inScatter(find.text(p.displayName)).evaluate().isNotEmpty &&
        view.contains(
          tester.getRect(_inScatter(find.text(p.displayName)).first).center,
        ))
      p.displayName,
};

void main() {
  group('#462 review (3): clustering is not redone on pan', () {
    testWidgets('scale <= 1: computed once; pans and zoom-out reuse it', (
      tester,
    ) async {
      _setView(tester, const Size(1280, 800));
      RatingScatterView.debugClusterComputations = 0;
      final rating = _RatingCubitStub();
      final profile = _ProfileCubitStub();
      await tester.pumpWidget(_host(_stacked, rating, profile));
      await tester.pump();
      expect(RatingScatterView.debugClusterComputations, 1);

      final controller = _controller(tester)
        ..value = _scaleAt(1, dx: -30, dy: -20);
      await tester.pump();
      controller.value = _scaleAt(1, dx: 45, dy: 12);
      await tester.pump();
      controller.value = _scaleAt(0.5, dx: 100, dy: 60);
      await tester.pump();
      expect(
        RatingScatterView.debugClusterComputations,
        1,
        reason: 'panning / zooming out at scale <= 1 must reuse the clusters',
      );

      // Same profiles list rebuilt by the parent: still no recompute.
      await tester.pumpWidget(_host(_stacked, rating, profile));
      await tester.pump();
      expect(RatingScatterView.debugClusterComputations, 1);

      // New profiles: recomputed.
      await tester.pumpWidget(
        _host(
          [..._stacked, const Profile(id: 'u-new', displayName: 'Newcomer')],
          rating,
          profile,
        ),
      );
      await tester.pump();
      expect(RatingScatterView.debugClusterComputations, 2);
    });

    testWidgets('scale > 1: pan reuses clusters, a scale change recomputes', (
      tester,
    ) async {
      _setView(tester, const Size(1280, 800));
      RatingScatterView.debugClusterComputations = 0;
      await tester.pumpWidget(
        _host(_stacked, _RatingCubitStub(), _ProfileCubitStub()),
      );
      await tester.pump();

      final controller = _controller(tester)
        ..value = _scaleAt(2, dx: -300, dy: -700);
      await tester.pump();
      final afterZoom = RatingScatterView.debugClusterComputations;
      expect(afterZoom, greaterThan(1), reason: 'zooming in reclusters');

      final lead = _stacked.firstWhere(
        (p) => _inScatter(find.text(p.displayName)).evaluate().isNotEmpty,
      );
      final before = tester.getRect(
        _inScatter(find.text(lead.displayName)).first,
      );

      // Pure pans at the same scale.
      controller.value = _scaleAt(2, dx: -340, dy: -760);
      await tester.pump();
      controller.value = _scaleAt(2, dx: -250, dy: -690);
      await tester.pump();
      expect(
        RatingScatterView.debugClusterComputations,
        afterZoom,
        reason: 'a pure translation must not recompute the clusters',
      );
      // ...and the reused clusters still follow the pan exactly.
      final after = tester.getRect(
        _inScatter(find.text(lead.displayName)).first,
      );
      expect(after.left - before.left, moreOrLessEquals(50, epsilon: 0.5));
      expect(after.top - before.top, moreOrLessEquals(10, epsilon: 0.5));

      // A real scale change does recompute.
      controller.value = _scaleAt(3, dx: -600, dy: -1500);
      await tester.pump();
      expect(
        RatingScatterView.debugClusterComputations,
        greaterThan(afterZoom),
      );
    });
  });

  group('#462 review (4): the +N chip', () {
    test('label is plural-aware in en and ru', () {
      final en = lookupL10n(const Locale('en'));
      final ru = lookupL10n(const Locale('ru'));
      expect(en.ratingScatterClusterMore(17), contains('17'));
      expect(en.ratingScatterClusterMore(1), contains('1'));
      // Singular differs from plural beyond the number ("person"/"people").
      expect(
        en.ratingScatterClusterMore(1),
        isNot(en.ratingScatterClusterMore(17).replaceAll('17', '1')),
      );
      expect(ru.ratingScatterClusterMore(5), contains('5'));
      expect(
        ru.ratingScatterClusterMore(5),
        isNot(en.ratingScatterClusterMore(5)),
      );
      // Russian one / few / many forms: 1 и 21 — one, 2 — few, 5 — many.
      expect(
        ru.ratingScatterClusterMore(2).replaceAll('2', '5'),
        isNot(ru.ratingScatterClusterMore(5)),
      );
      expect(
        ru.ratingScatterClusterMore(21).replaceAll('21', '1'),
        ru.ratingScatterClusterMore(1),
      );
    });

    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets('chip reads "N more people here" ($locale)', (tester) async {
        _setView(tester, const Size(1280, 800));
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            _stacked,
            _RatingCubitStub(),
            _ProfileCubitStub(),
            locale: locale,
          ),
        );
        await tester.pump();

        final l10n = lookupL10n(locale);
        final chips = _chips(tester);
        expect(chips, isNotEmpty, reason: 'the stacked repro shows a +N chip');
        for (final n in chips.values) {
          expect(
            find.bySemanticsLabel(
              RegExp(RegExp.escape(l10n.ratingScatterClusterMore(n))),
            ),
            findsWidgets,
          );
        }
        semantics.dispose();
      });
    }

    testWidgets('tapping the chip zooms into the cluster and splits it', (
      tester,
    ) async {
      _setView(tester, const Size(1280, 800));
      final rating = _RatingCubitStub();
      await tester.pumpWidget(_host(_stacked, rating, _ProfileCubitStub()));
      await tester.pump();

      final view = tester.getRect(find.byType(RatingScatterView));
      final namesBefore = _namesInView(tester, _stacked, view);
      final chips = _chips(tester);
      expect(chips, isNotEmpty);
      final biggest = chips.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );

      await tester.tap(_inScatter(find.text(biggest.key)).first);
      await tester.pumpAndSettle();

      expect(
        _controller(tester).value.getMaxScaleOnAxis(),
        greaterThan(1.0),
        reason: 'the chip zooms in',
      );
      expect(
        rating.opened,
        isEmpty,
        reason: 'the chip zooms; it does not just open the lead profile',
      );
      final namesAfter = _namesInView(tester, _stacked, view);
      expect(
        namesAfter.length,
        greaterThan(namesBefore.length),
        reason: 'hidden cluster members become individually visible',
      );
      expect(
        namesAfter.difference(namesBefore),
        isNotEmpty,
        reason: 'someone who was folded into the chip is now shown by name',
      );
    });
  });

  group('#462 review (5): y-axis title vs the rank-to-you = 0 column', () {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      testWidgets('title does not cover avatars at ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        _setView(tester, size);
        await tester.pumpWidget(
          _host(_leftColumn, _RatingCubitStub(), _ProfileCubitStub()),
        );
        await tester.pump();

        final l10n = lookupL10n(const Locale('en'));
        final title = tester.getRect(
          _inScatter(find.textContaining(l10n.rankFromYou)),
        );
        final avatarFinder = _inScatter(find.byType(TenturaAvatar));
        final avatars = [
          for (var i = 0; i < avatarFinder.evaluate().length; i++)
            tester.getRect(avatarFinder.at(i)),
        ];
        expect(avatars, isNotEmpty);
        final hits = [
          for (final a in avatars)
            if (a.overlaps(title.deflate(0.5))) a,
        ];
        expect(
          hits,
          isEmpty,
          reason: 'y-axis title $title overlaps avatars $hits',
        );
      });
    }
  });
}
