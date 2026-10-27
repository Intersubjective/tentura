// GitHub #462 — QA on iPhone SE (375x667), web 7.56.1: desktop passes, the
// phone does not.
//
// (a) After "Zoom in here" the people below the view were drawn over the
//     x-tick gutter, the "Rank to you" title and the legend: what the plot
//     paints stays inside the plot area.
// (b) The legend wraps on a phone; its badges touched the left edge and
//     the last row's badge was cut by the bottom of the viewport: the
//     legend sits whole inside the view, inset from its edges.
// (c) The overview was illegible (the 800x800 canvas scaled down to ~40 %,
//     avatars ~13 px) and "New member" at rank-to-you 0 lost its first
//     letter at the left edge: on a phone people are drawn at full size
//     (clustered in screen space), and no name is cut by the plot's edges.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_spacing.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/rating/ui/bloc/rating_cubit.dart';
import 'package:tentura/features/rating/ui/widget/rating_scatter_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

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

const _se = Size(375, 667);
const _desktop = Size(1280, 800);

/// The QA repro: a fresh account one-way trusts people, so many rank you 0
/// ("New member" among them); plus a few spread over the plot.
const _people = [
  Profile(id: 'u-new', displayName: 'New member', score: 50),
  Profile(id: 'u-eve', displayName: 'Eve', score: 80),
  Profile(id: 'u-bob', displayName: 'Bob', score: 72),
  Profile(id: 'u-zed', displayName: 'Zed', score: 12),
  Profile(id: 'u-dave', displayName: 'Dave', score: 30),
  Profile(id: 'u-a', displayName: 'Alice', score: 90, rScore: 10),
  Profile(id: 'u-f', displayName: 'Frank', score: 90, rScore: 90),
  Profile(id: 'u-c', displayName: 'Cara', score: 10, rScore: 10),
  Profile(id: 'u-d', displayName: 'Dan', score: 10, rScore: 90),
  Profile(id: 'u-top', displayName: 'Topper', score: 100, rScore: 100),
];

final _legendIds = {
  ContactBadgeLegend.mutualProfile.id,
  ContactBadgeLegend.eyeOpenProfile.id,
  ContactBadgeLegend.eyeClosedProfile.id,
};

Future<void> _pumpScatter(
  WidgetTester tester, {
  Size size = _se,
  Locale locale = const Locale('en'),
  List<Profile> profiles = _people,
}) async {
  tester.view.physicalSize = size;
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

Rect _plotRect(WidgetTester tester) =>
    tester.getRect(_inScatter(find.byType(InteractiveViewer)));

TransformationController _controller(WidgetTester tester) => tester
    .widget<InteractiveViewer>(_inScatter(find.byType(InteractiveViewer)))
    .transformationController!;

Finder _plotAvatars() => _inScatter(
  find.byWidgetPredicate(
    (w) => w is TenturaAvatar && !_legendIds.contains(w.profile.id),
  ),
);

Finder _legendAvatars() => _inScatter(
  find.byWidgetPredicate(
    (w) => w is TenturaAvatar && _legendIds.contains(w.profile.id),
  ),
);

/// Plotted people's name labels that are in the tree.
List<Finder> _names() => [
  for (final p in _people)
    if (_inScatter(find.text(p.displayName)).evaluate().isNotEmpty)
      _inScatter(find.text(p.displayName)).first,
];

List<Finder> _all(Finder f) => [
  for (var i = 0; i < f.evaluate().length; i++) f.at(i),
];

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// The part of [finder]'s box that can reach the screen: its rect cut by
/// every clipping ancestor (an empty rect when it is clipped away).
Rect _paintedRect(WidgetTester tester, Finder finder) {
  var rect = tester.getRect(finder);
  RenderObject? node = tester.renderObject(finder).parent;
  while (node != null) {
    final clips = switch (node) {
      final RenderClipRect n => n.clipBehavior != Clip.none,
      final RenderClipRRect n => n.clipBehavior != Clip.none,
      final RenderClipPath n => n.clipBehavior != Clip.none,
      _ => false,
    };
    if (clips) {
      final clip = _globalRect(node as RenderBox);
      rect = rect.overlaps(clip) ? rect.intersect(clip) : Rect.zero;
    }
    node = node.parent;
  }
  return rect;
}

bool _within(Rect inner, Rect outer, {double eps = 0.5}) =>
    inner.left >= outer.left - eps &&
    inner.top >= outer.top - eps &&
    inner.right <= outer.right + eps &&
    inner.bottom <= outer.bottom + eps;

void main() {
  group('#462a zoomed-in people stay inside the plot', () {
    for (final size in const [_se, _desktop]) {
      testWidgets('after zooming in, nothing is painted outside the plot '
          '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
        await _pumpScatter(tester, size: size);
        final plot = _plotRect(tester);
        // Zoom x2.5 into the lower-left, as "Zoom in here" on the rank-0
        // column does: people below and left of the view run out of it.
        _controller(tester).value = Matrix4.diagonal3Values(2.5, 2.5, 1)
          ..setTranslationRaw(-plot.width * 0.2, -plot.height * 1.2, 0);
        await tester.pump();

        final drawn = [..._all(_plotAvatars()), ..._names()];
        expect(drawn, isNotEmpty);
        var outside = 0;
        for (final f in drawn) {
          final raw = tester.getRect(f);
          if (!_within(raw, plot)) outside++;
          final painted = _paintedRect(tester, f);
          if (painted.isEmpty) continue;
          expect(
            _within(painted, plot),
            isTrue,
            reason: 'painted at $painted, outside the plot $plot',
          );
        }
        // The case is real: some people do lie outside the zoomed view.
        expect(outside, greaterThan(0));
      });
    }
  });

  group('#462b the legend is whole on a phone', () {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets('inset from the edges, inside the view ($locale)', (
        tester,
      ) async {
        await _pumpScatter(tester, locale: locale);
        final view = tester.getRect(find.byType(RatingScatterView));
        final plot = _plotRect(tester);
        final l10n = lookupL10n(locale);

        final badges = _all(_legendAvatars());
        expect(badges, hasLength(3));
        for (final f in badges) {
          // The contact badge hangs a couple of pixels off the avatar.
          final a = tester.getRect(f).inflate(2);
          expect(
            a.left - view.left,
            greaterThanOrEqualTo(TenturaSpacing.row),
            reason: 'badge $a touches the left edge of $view',
          );
          expect(
            view.right - a.right,
            greaterThanOrEqualTo(TenturaSpacing.row),
            reason: 'badge $a touches the right edge of $view',
          );
          expect(
            view.bottom - a.bottom,
            greaterThanOrEqualTo(TenturaSpacing.row / 2),
            reason: 'badge $a sits on the bottom edge of $view',
          );
        }
        for (final label in [
          l10n.graphLegendEdgeMutual,
          l10n.profileEyeOpen,
          l10n.profileEyeClosed,
        ]) {
          final f = _inScatter(find.text(label));
          expect(f, findsOneWidget, reason: label);
          final rect = tester.getRect(f);
          expect(_within(rect, view), isTrue, reason: '$label at $rect');
          expect(rect.overlaps(plot.deflate(0.5)), isFalse, reason: label);
          final paragraph = tester.renderObject<RenderParagraph>(f);
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('#462c the overview is legible on a phone', () {
    testWidgets('people are drawn at full size, names at full height', (
      tester,
    ) async {
      await _pumpScatter(tester);
      final avatars = _all(_plotAvatars());
      expect(avatars, isNotEmpty);
      for (final f in avatars) {
        final r = tester.getRect(f);
        expect(r.width, greaterThanOrEqualTo(24), reason: 'avatar $r');
        expect(r.height, greaterThanOrEqualTo(24), reason: 'avatar $r');
      }
      for (final f in _names()) {
        expect(
          tester.getRect(f).height,
          greaterThanOrEqualTo(15),
          reason: 'name ${tester.widget<Text>(f).data}',
        );
      }
    });

    for (final size in const [_se, _desktop]) {
      testWidgets('no name is cut by the plot edges '
          '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
        await _pumpScatter(tester, size: size);
        final plot = _plotRect(tester);
        final names = _names();
        expect(
          _inScatter(find.text('New member')),
          findsOneWidget,
          reason: 'the rank-to-you 0 lead the QA saw cut',
        );
        for (final f in names) {
          final r = tester.getRect(f);
          expect(
            _within(r, plot),
            isTrue,
            reason: '"${tester.widget<Text>(f).data}" at $r, plot $plot',
          );
        }
      });
    }

    testWidgets('a person in the bottom-left corner keeps the name in view', (
      tester,
    ) async {
      await _pumpScatter(
        tester,
        profiles: const [Profile(id: 'u-zero', displayName: 'New member')],
      );
      final plot = _plotRect(tester);
      final avatar = tester.getRect(_plotAvatars());
      final name = tester.getRect(_inScatter(find.text('New member')));
      expect(_within(avatar, plot), isTrue, reason: 'avatar $avatar');
      expect(_within(name, plot), isTrue, reason: 'name $name');
      expect(avatar.overlaps(name.deflate(0.5)), isFalse);
    });
  });
}
