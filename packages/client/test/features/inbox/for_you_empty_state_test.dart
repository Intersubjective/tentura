import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/ui/widget/for_you_empty_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

/// U16c-1 — `docs/features/request-attention.md` §4, "What 'cleared' looks
/// like": three states **must read differently**.
///
///   * *nothing here* — the surface has never had anything on it;
///   * *nothing new* — cleared, **and the decision zone may still be there**;
///   * *nothing matching this filter*.
///
/// The §4 _Avoid_ line forbids celebrating "all clear" while decisions are
/// pending or while loading, so the cleared copy must not claim an empty
/// surface, and there must be no empty state at all during a load.
Future<void> _pump(
  WidgetTester tester,
  ForYouEmptyKind kind, {
  double textScale = 1,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: ForYouEmptyState(kind: kind)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = L10nEn();

  group('the decision rule', () {
    test('a filtered surface reports the filter, whatever else is true', () {
      expect(
        forYouEmptyKind(hasActiveFilter: true, hasPinnedZone: true),
        ForYouEmptyKind.noMatch,
      );
      expect(
        forYouEmptyKind(hasActiveFilter: true, hasPinnedZone: false),
        ForYouEmptyKind.noMatch,
      );
    });

    test('a pinned decision zone means *cleared*, not *empty*', () {
      // §4: "Because Dismiss all leaves decisions alone, a cleared For you can
      // still show its pinned zone."
      expect(
        forYouEmptyKind(hasActiveFilter: false, hasPinnedZone: true),
        ForYouEmptyKind.nothingNew,
      );
    });

    test('a surface with nothing at all reports *nothing here*', () {
      expect(
        forYouEmptyKind(hasActiveFilter: false, hasPinnedZone: false),
        ForYouEmptyKind.nothingHere,
      );
    });
  });

  group('when an empty state may be shown at all', () {
    // §4 _Avoid_: "celebrating 'all clear' while decisions are pending, while
    // loading, offline, or after a partial sweep". The exhaustive truth table
    // is the guard: exactly one of the eight combinations may show it.
    test('only a loaded, error-free, genuinely empty surface shows one', () {
      final shown = <List<bool>>[];
      for (final hasRows in [false, true]) {
        for (final isLoading in [false, true]) {
          for (final hasError in [false, true]) {
            if (shouldShowForYouEmptyState(
              hasRows: hasRows,
              isLoading: isLoading,
              hasError: hasError,
            )) {
              shown.add([hasRows, isLoading, hasError]);
            }
          }
        }
      }
      expect(shown, [
        [false, false, false],
      ]);
    });

    test('a loading empty surface is not an empty surface', () {
      expect(
        shouldShowForYouEmptyState(
          hasRows: false,
          isLoading: true,
          hasError: false,
        ),
        isFalse,
      );
    });

    test('a failed refresh is not an empty surface either', () {
      expect(
        shouldShowForYouEmptyState(
          hasRows: false,
          isLoading: false,
          hasError: true,
        ),
        isFalse,
      );
    });
  });

  group('the three states read differently', () {
    testWidgets('nothing here', (tester) async {
      await _pump(tester, ForYouEmptyKind.nothingHere);
      expect(find.byKey(ForYouEmptyState.titleKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingHere), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingHereHint), findsOneWidget);
    });

    testWidgets('nothing new, and it does not claim an empty surface', (
      tester,
    ) async {
      await _pump(tester, ForYouEmptyKind.nothingNew);
      expect(find.byKey(ForYouEmptyState.titleKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingNew), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingNewHint), findsOneWidget);
      expect(
        find.text(l10n.forYouEmptyNothingHere),
        findsNothing,
        reason: 'cleared is not the same sentence as never-had-anything',
      );
    });

    testWidgets('nothing matching this filter', (tester) async {
      await _pump(tester, ForYouEmptyKind.noMatch);
      expect(find.byKey(ForYouEmptyState.titleKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNoMatch), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNoMatchHint), findsOneWidget);
    });

    test('no two states share a title or a hint', () {
      final titles = {
        for (final kind in ForYouEmptyKind.values) kind: kind.title(l10n),
      };
      final hints = {
        for (final kind in ForYouEmptyKind.values) kind: kind.hint(l10n),
      };
      expect(
        titles.values.toSet(),
        hasLength(ForYouEmptyKind.values.length),
        reason: '§4: the three states must read differently',
      );
      expect(hints.values.toSet(), hasLength(ForYouEmptyKind.values.length));
    });
  });

  testWidgets(
    'the cleared copy survives narrow width at 2x text scale, in full',
    (tester) async {
      // A long hint inside a scroll view at 320dp / 2x silently stops building
      // what follows it, with no overflow error, so this asserts the positive:
      // both the title and the whole hint are still laid out and painted.
      await _pump(
        tester,
        ForYouEmptyKind.nothingNew,
        width: 320,
        textScale: 2,
      );
      expect(find.byKey(ForYouEmptyState.titleKey), findsOneWidget);
      expect(find.byKey(ForYouEmptyState.hintKey), findsOneWidget);
      expect(find.text(l10n.forYouEmptyNothingNewHint), findsOneWidget);
      expect(tester.takeException(), isNull);

      final hint = tester.widget<Text>(find.byKey(ForYouEmptyState.hintKey));
      expect(
        hint.overflow,
        isNot(TextOverflow.ellipsis),
        reason:
            'the sentence that explains why the decision zone is still there '
            'must not be the part that gets truncated',
      );
      expect(
        tester.getSize(find.byKey(ForYouEmptyState.hintKey)).height,
        greaterThan(0),
      );
    },
  );
}
