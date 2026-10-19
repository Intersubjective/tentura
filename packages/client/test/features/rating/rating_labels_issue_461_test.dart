// GitHub #461 — the Rating table labelled computed MeritRank scores as
// "I trust them" / "They trust me", used internal class words
// ("one-way out" / "one-way in") and kept a disabled clear (X) button beside
// the working back arrow.
//
// Spec: columns read "Rank from you" / "Rank to you" with a tooltip that
// explains the number (not just the label again); class words are
// "mutual" / "you → them" / "them → you"; no disabled X in the top bar.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/rating/ui/bloc/rating_cubit.dart';
import 'package:tentura/features/rating/ui/screen/rating_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _RatingCubitStub extends Mock implements RatingCubit {
  _RatingCubitStub(this._state);

  final RatingState _state;

  @override
  RatingState get state => _state;

  @override
  Stream<RatingState> get stream => const Stream<RatingState>.empty();
}

class _ProfileCubitStub extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _NavRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

/// One row per reciprocity class (support threshold is 10 on 0-100).
const _profiles = [
  Profile(id: 'u-mutual', displayName: 'Mutual Mia', score: 80, rScore: 70),
  // The issue's repro: a stranger with a high computed rank from me, 0 back.
  Profile(id: 'u-out', displayName: 'Jasper', score: 94),
  Profile(id: 'u-in', displayName: 'Incoming Ina', rScore: 50),
  Profile(id: 'u-none', displayName: 'Nobody Ned'),
];

Future<void> _pumpRating(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  String searchFilter = '',
}) async {
  // Phone width: Rating renders without the Home rail.
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _NavRouter();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<RatingCubit>.value(
                value: _RatingCubitStub(
                  RatingState(items: _profiles, searchFilter: searchFilter),
                ),
              ),
              BlocProvider<ProfileCubit>.value(value: _ProfileCubitStub()),
            ],
            child: const RatingScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The longest tooltip text in the header cell holding [labelText] that is
/// not just the label repeated — the sort header itself or an info icon
/// beside it may carry the explanation.
String _columnExplanation(WidgetTester tester, String labelText) {
  final cell = find
      .ancestor(of: find.text(labelText), matching: find.byType(Expanded))
      .first;
  final texts =
      [
          for (final t in tester.widgetList<Tooltip>(
            find.descendant(of: cell, matching: find.byType(Tooltip)),
          ))
            t.message ?? t.richMessage?.toPlainText() ?? '',
        ].where((m) => m.trim().isNotEmpty && m.trim() != labelText).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  return texts.isEmpty ? '' : texts.first;
}

void main() {
  group('#461 Rating columns', () {
    testWidgets('score columns read Rank from you / Rank to you', (
      tester,
    ) async {
      await _pumpRating(tester);

      expect(find.text('Rank from you'), findsOneWidget);
      expect(find.text('Rank to you'), findsOneWidget);
      // The old copy asserted a trust relationship that does not exist.
      expect(find.text('I trust them'), findsNothing);
      expect(find.text('They trust me'), findsNothing);
    });

    testWidgets('each rank column has a tooltip explaining the number', (
      tester,
    ) async {
      await _pumpRating(tester);

      expect(find.text('Rank from you'), findsOneWidget);
      final from = _columnExplanation(tester, 'Rank from you');
      final to = _columnExplanation(tester, 'Rank to you');
      // Not just the column label repeated (today: Tooltip(message: label)).
      expect(from, isNot(isEmpty));
      expect(to, isNot(isEmpty));
      expect(from.length, greaterThan('Rank from you'.length));
      expect(to.length, greaterThan('Rank to you'.length));
      expect(from, isNot(to));
      expect(from.toLowerCase(), isNot(contains('i trust them')));
      expect(to.toLowerCase(), isNot(contains('they trust me')));
    });

    testWidgets('Russian: no trust-claim column copy', (tester) async {
      await _pumpRating(tester, locale: const Locale('ru'));

      expect(find.text('Я доверяю им'), findsNothing);
      expect(find.text('Они доверяют мне'), findsNothing);
      // Guard: the table still renders its four rows.
      expect(find.text('Jasper'), findsOneWidget);
    });
  });

  group('#461 Rating class words', () {
    testWidgets('class column reads mutual / you → them / them → you', (
      tester,
    ) async {
      await _pumpRating(tester);

      expect(find.text('mutual'), findsOneWidget);
      expect(find.text('you → them'), findsOneWidget);
      expect(find.text('them → you'), findsOneWidget);
      expect(find.text('one-way out'), findsNothing);
      expect(find.text('one-way in'), findsNothing);
    });

    testWidgets('Russian class words use arrows, not internal jargon', (
      tester,
    ) async {
      await _pumpRating(tester, locale: const Locale('ru'));

      expect(find.text('односторонне (исх.)'), findsNothing);
      expect(find.text('односторонне (вх.)'), findsNothing);
      expect(find.textContaining('→'), findsAtLeastNWidgets(2));
    });

    test('graph legend note no longer cites the old class words', () {
      final en = lookupL10n(const Locale('en'));
      expect(en.graphLegendNoteTextLabels, isNot(contains('one-way out')));
      expect(en.graphLegendNoteTextLabels, isNot(contains('one-way in')));
    });
  });

  group('#461 Rating top bar', () {
    testWidgets('no disabled clear button beside the back arrow', (
      tester,
    ) async {
      await _pumpRating(tester);

      // Guard: the working back arrow stays.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is IconButton && w.onPressed == null),
        findsNothing,
      );
      expect(find.byIcon(Icons.clear_rounded), findsNothing);
    });

    testWidgets('guard: with a search typed, any clear control is enabled', (
      tester,
    ) async {
      await _pumpRating(tester, searchFilter: 'jas');

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is IconButton && w.onPressed == null),
        findsNothing,
      );
      // The filter itself still applies.
      expect(find.text('Jasper'), findsOneWidget);
      expect(find.text('Mutual Mia'), findsNothing);
    });
  });
}
