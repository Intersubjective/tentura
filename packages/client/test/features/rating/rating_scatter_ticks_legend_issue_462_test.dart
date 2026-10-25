// GitHub #462 / #615 — Rating > Scatter view residuals after PR #614:
// the axes carry titles but no scale, and nothing explains the eye / mutual
// badges on the avatars.
//
// Spec: both axes show 0 / 50 / 100 tick labels in their gutters, outside
// the plot area, at the positions those ranks map to (and they follow the
// zoom); a small legend row names the three avatar badges (mutual trust,
// eye open, eye closed) with the same words the rest of the app uses; the
// x-axis title, the ticks and the legend never cover a person at rank 0.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

const _spread = [
  Profile(id: 'u-a', displayName: 'Alice Idol', score: 90, rScore: 10),
  Profile(id: 'u-b', displayName: 'Bob Friend', score: 90, rScore: 90),
  Profile(id: 'u-c', displayName: 'Cara Acq', score: 10, rScore: 10),
  Profile(id: 'u-d', displayName: 'Dan Fan', score: 10, rScore: 90),
];

/// A stranger in the bottom-left corner: ranks you 0, you rank them 0.
const _corner = Profile(id: 'u-zero', displayName: 'Zero Corner');

Future<void> _pumpScatter(
  WidgetTester tester,
  List<Profile> profiles, {
  Size size = const Size(1280, 800),
  Locale locale = const Locale('en'),
  double textScale = 1,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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

/// Avatars of the plotted people (the legend's sample avatars excluded).
Finder _plotAvatars() => find.descendant(
  of: _inScatter(find.byType(InteractiveViewer)),
  matching: find.byType(TenturaAvatar),
);

Rect _plotRect(WidgetTester tester) =>
    tester.getRect(_inScatter(find.byType(InteractiveViewer)));

TransformationController _controller(WidgetTester tester) => tester
    .widget<InteractiveViewer>(_inScatter(find.byType(InteractiveViewer)))
    .transformationController!;

List<Rect> _rectsOf(WidgetTester tester, String text) {
  final finder = _inScatter(find.text(text));
  return [
    for (var i = 0; i < finder.evaluate().length; i++)
      tester.getRect(finder.at(i)),
  ];
}

/// The tick label for [value] on the x axis (below the plot).
Rect _xTick(WidgetTester tester, String value) {
  final plot = _plotRect(tester);
  return _rectsOf(
    tester,
    value,
  ).singleWhere((r) => r.top >= plot.bottom - 0.5);
}

/// The tick label for [value] on the y axis (left of the plot).
Rect _yTick(WidgetTester tester, String value) {
  final plot = _plotRect(tester);
  return _rectsOf(
    tester,
    value,
  ).singleWhere((r) => r.right <= plot.left + 0.5);
}

bool _intersects(Rect a, Rect b) {
  final i = a.intersect(b);
  return i.width > 0.5 && i.height > 0.5;
}

void main() {
  group('#462 Scatter axis ticks', () {
    testWidgets('both axes show 0, 50 and 100', (tester) async {
      await _pumpScatter(tester, _spread);

      for (final v in ['0', '50', '100']) {
        expect(_inScatter(find.text(v)), findsNWidgets(2), reason: v);
      }
    });

    testWidgets('ticks sit outside the plot, in order, 50 at the centre', (
      tester,
    ) async {
      await _pumpScatter(tester, _spread);

      final plot = _plotRect(tester);
      final x0 = _xTick(tester, '0');
      final x50 = _xTick(tester, '50');
      final x100 = _xTick(tester, '100');
      expect(x0.center.dx, lessThan(x50.center.dx));
      expect(x50.center.dx, lessThan(x100.center.dx));
      // The scale is symmetric: rank 50 maps to the middle of the plot.
      expect(x50.center.dx, moreOrLessEquals(plot.center.dx, epsilon: 1));

      final y0 = _yTick(tester, '0');
      final y50 = _yTick(tester, '50');
      final y100 = _yTick(tester, '100');
      // y grows upwards.
      expect(y100.center.dy, lessThan(y50.center.dy));
      expect(y50.center.dy, lessThan(y0.center.dy));
      expect(y50.center.dy, moreOrLessEquals(plot.center.dy, epsilon: 1));
    });

    testWidgets('ticks line up with a person at rank 0 / 100', (
      tester,
    ) async {
      await _pumpScatter(tester, const [
        _corner,
        Profile(id: 'u-top', displayName: 'Top Right', score: 100, rScore: 100),
      ]);

      final avatars = _plotAvatars();
      final corner = tester.getRect(avatars.at(0));
      final top = tester.getRect(avatars.at(1));
      final cornerLeft = corner.center.dx < top.center.dx ? corner : top;
      final topRight = identical(cornerLeft, corner) ? top : corner;
      expect(
        _xTick(tester, '0').center.dx,
        moreOrLessEquals(cornerLeft.center.dx, epsilon: 10),
      );
      expect(
        _xTick(tester, '100').center.dx,
        moreOrLessEquals(topRight.center.dx, epsilon: 10),
      );
      expect(
        _yTick(tester, '0').center.dy,
        moreOrLessEquals(cornerLeft.center.dy, epsilon: 10),
      );
      expect(
        _yTick(tester, '100').center.dy,
        moreOrLessEquals(topRight.center.dy, epsilon: 10),
      );
    });

    testWidgets('ticks follow the zoom and hide when scrolled out', (
      tester,
    ) async {
      await _pumpScatter(tester, _spread);

      final plot = _plotRect(tester);
      // Zoom x2 around the plot centre: 50 stays centred, 0 and 100 leave.
      // (At scale > 1 the people move to an overlay, which is fine here.)
      _controller(tester).value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-plot.width / 2, -plot.height / 2, 0);
      await tester.pump();

      expect(_inScatter(find.text('50')), findsNWidgets(2));
      expect(_inScatter(find.text('0')), findsNothing);
      expect(_inScatter(find.text('100')), findsNothing);
      expect(
        _xTick(tester, '50').center.dx,
        moreOrLessEquals(plot.center.dx, epsilon: 1),
      );
    });
  });

  // #462 / #615 review: the tick gutters were fixed boxes, so at a large
  // text scale "100" was clipped or ran into the plot.
  group('#462 Scatter ticks at large text scale', () {
    for (final scale in const [1.0, 2.0]) {
      for (final size in const [Size(1280, 800), Size(360, 740)]) {
        testWidgets('labels are whole and clear of the plot (x$scale, $size)', (
          tester,
        ) async {
          await _pumpScatter(tester, _spread, size: size, textScale: scale);

          final plot = _plotRect(tester);
          final l10n = lookupL10n(const Locale('en'));
          final titles = [
            tester.getRect(_inScatter(find.text(l10n.rankToYou))),
            tester.getRect(_inScatter(find.text(l10n.rankFromYou))),
          ];
          for (final v in ['0', '50', '100']) {
            final finder = _inScatter(find.text(v));
            expect(finder, findsNWidgets(2), reason: v);
            for (var i = 0; i < 2; i++) {
              final paragraph = tester.renderObject<RenderParagraph>(
                finder.at(i),
              );
              final width = paragraph.getMaxIntrinsicWidth(double.infinity);
              final height = paragraph.getMaxIntrinsicHeight(double.infinity);
              expect(
                paragraph.size.width,
                greaterThanOrEqualTo(width - 0.5),
                reason: '"$v" is cut sideways',
              );
              expect(
                paragraph.size.height,
                greaterThanOrEqualTo(height - 0.5),
                reason: '"$v" is cut vertically',
              );
              final rect = tester.getRect(finder.at(i));
              expect(_intersects(rect, plot), isFalse, reason: '"$v" vs plot');
              for (final title in titles) {
                expect(_intersects(rect, title), isFalse, reason: '"$v"');
              }
            }
          }
          // One label on each axis, outside the plot.
          for (final v in ['0', '50', '100']) {
            _xTick(tester, v);
            _yTick(tester, v);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('#462 Scatter badge legend', () {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets('names the three badges ($locale)', (tester) async {
        await _pumpScatter(tester, _spread, locale: locale);

        final l10n = lookupL10n(locale);
        for (final label in [
          l10n.graphLegendEdgeMutual,
          l10n.profileEyeOpen,
          l10n.profileEyeClosed,
        ]) {
          expect(_inScatter(find.text(label)), findsOneWidget, reason: label);
          // Outside the plot area, so it never covers anyone.
          expect(
            _intersects(
              tester.getRect(_inScatter(find.text(label))),
              _plotRect(tester),
            ),
            isFalse,
            reason: label,
          );
        }
      });
    }
  });

  group('#462 Scatter rank-0 person stays clear', () {
    for (final size in const [Size(1280, 800), Size(390, 844)]) {
      testWidgets('x title, ticks and legend do not cover them ($size)', (
        tester,
      ) async {
        await _pumpScatter(tester, const [_corner], size: size);

        final l10n = lookupL10n(const Locale('en'));
        final avatar = tester.getRect(_plotAvatars());
        // The name sits in a fixed-width box wider than the text, which may
        // reach the y gutter's edge; it is checked against everything below
        // the plot.
        final name = tester.getRect(
          _inScatter(find.text(_corner.displayName)),
        );
        final below = [
          tester.getRect(_inScatter(find.text(l10n.rankToYou))),
          for (final v in ['0', '50', '100']) _xTick(tester, v),
          for (final label in [
            l10n.graphLegendEdgeMutual,
            l10n.profileEyeOpen,
            l10n.profileEyeClosed,
          ])
            ..._rectsOf(tester, label),
        ];
        final left = [
          tester.getRect(_inScatter(find.text(l10n.rankFromYou))),
          for (final v in ['0', '50', '100']) _yTick(tester, v),
        ];
        for (final o in [...below, ...left]) {
          expect(_intersects(avatar, o), isFalse, reason: 'avatar vs $o');
        }
        for (final o in below) {
          expect(_intersects(name, o), isFalse, reason: 'name vs $o');
        }
      });
    }
  });
}
