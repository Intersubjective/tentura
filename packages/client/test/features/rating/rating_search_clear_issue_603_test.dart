// GitHub #603 (from #461) — the Rating search field used
// `TextFormField(initialValue: …)`, so after the filter was cleared (the ✕
// button or any programmatic reset) the field kept showing the stale text
// while the list had already gone back to unfiltered.
//
// Spec: the field is controlled by the cubit's search filter — clearing the
// filter empties the field; typing still filters.
//
// Follow-up (QA 7.46.1): on web, a mouse click on ✕ counted as a tap outside
// the field and dropped its focus, and the first click back on the field did
// not focus it, so the next keys were lost. Spec: Close keeps the caret in
// the field, so typing goes on with no extra click.
//
// Follow-up (QA 7.50.3, 7.50.7, browser trace 2026-10-31): with semantics on,
// the engine moved the browser focus off the field's input on the ✕ click,
// and the scatter-view button that slid under the pointer showed a tooltip
// that moved the input in the DOM. The browser repair is app-wide
// (`restoreTextInputFocusAfterSemanticsBlur`) and proven only by the
// Playwright regression in scripts/e2e_focus. Spec here: the ✕ is the
// field's own suffix icon, so no other action sits where it was.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/rating/ui/bloc/rating_cubit.dart';
import 'package:tentura/features/rating/ui/screen/rating_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// A real cubit for the search filter; everything else is a no-op.
class _RatingCubitFake extends Cubit<RatingState> implements RatingCubit {
  _RatingCubitFake(super.initialState);

  @override
  void setSearchFilter(String filter) =>
      emit(state.copyWith(searchFilter: filter));

  @override
  void clearSearchFilter() => emit(state.copyWith(searchFilter: ''));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

const _profiles = [
  Profile(id: 'u-mutual', displayName: 'Mutual Mia', score: 80, rScore: 70),
  Profile(id: 'u-out', displayName: 'Jasper', score: 94),
];

Future<_RatingCubitFake> _pumpRating(
  WidgetTester tester, {
  String searchFilter = '',
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _NavRouter();
  final cubit = _RatingCubitFake(
    RatingState(items: _profiles, searchFilter: searchFilter),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
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
              BlocProvider<RatingCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _ProfileCubitStub()),
            ],
            child: const RatingScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

bool _fieldHasFocus(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  group('#603 Rating search field', () {
    testWidgets('guard: typing filters the list and shows the text', (
      tester,
    ) async {
      final cubit = await _pumpRating(tester);

      await tester.enterText(find.byType(TextField), 'jas');
      await tester.pump();

      expect(cubit.state.searchFilter, 'jas');
      expect(_fieldText(tester), 'jas');
      expect(find.text('Jasper'), findsOneWidget);
      expect(find.text('Mutual Mia'), findsNothing);
    });

    testWidgets('guard: an initial filter is shown in the field', (
      tester,
    ) async {
      await _pumpRating(tester, searchFilter: 'jas');

      expect(_fieldText(tester), 'jas');
    });

    testWidgets('clear button empties the field, not just the filter', (
      tester,
    ) async {
      final cubit = await _pumpRating(tester);

      await tester.enterText(find.byType(TextField), 'jas');
      await tester.pump();
      expect(find.text('Mutual Mia'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      expect(cubit.state.searchFilter, isEmpty);
      // Before #603 the field still read "jas" here.
      expect(_fieldText(tester), isEmpty);
      expect(find.text('Mutual Mia'), findsOneWidget);
      expect(find.text('Jasper'), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsNothing);
    });

    testWidgets('a programmatic reset of the filter empties the field', (
      tester,
    ) async {
      final cubit = await _pumpRating(tester, searchFilter: 'jas');
      expect(_fieldText(tester), 'jas');

      cubit.clearSearchFilter();
      // The cubit emits on a microtask; the first pump has no frame scheduled
      // yet, so it only delivers the state. The second draws the rebuild.
      await tester.pump();
      await tester.pump();

      expect(_fieldText(tester), isEmpty);
      expect(find.text('Mutual Mia'), findsOneWidget);
    });

    testWidgets('typing again after a clear starts from an empty field', (
      tester,
    ) async {
      final cubit = await _pumpRating(tester);

      await tester.enterText(find.byType(TextField), 'jas');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'mi');
      await tester.pump();

      expect(cubit.state.searchFilter, 'mi');
      expect(_fieldText(tester), 'mi');
      expect(find.text('Mutual Mia'), findsOneWidget);
      expect(find.text('Jasper'), findsNothing);
    });
  });

  group('#603 Rating search: Close by mouse keeps typing in the field', () {
    testWidgets(
      'after Close the field keeps focus and the next keys land in it',
      (tester) async {
        final cubit = await _pumpRating(tester);

        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();
        expect(_fieldHasFocus(tester), isTrue);

        await tester.tap(
          find.byIcon(Icons.clear_rounded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        expect(cubit.state.searchFilter, isEmpty);
        // Before the fix the mouse click on ✕ unfocused the field.
        expect(_fieldHasFocus(tester), isTrue);

        // Keys typed straight after Close, with no extra click.
        tester.testTextInput.enterText('mi');
        await tester.pump();

        expect(_fieldText(tester), 'mi');
        expect(cubit.state.searchFilter, 'mi');
        expect(find.text('Mutual Mia'), findsOneWidget);
        expect(find.text('Jasper'), findsNothing);
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'one click on the field after Close is enough to type',
      (tester) async {
        final cubit = await _pumpRating(tester);

        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();
        await tester.tap(
          find.byIcon(Icons.clear_rounded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        await tester.tap(
          find.byType(TextField),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        expect(_fieldHasFocus(tester), isTrue);
        tester.testTextInput.enterText('al');
        await tester.pump();

        expect(_fieldText(tester), 'al');
        expect(cubit.state.searchFilter, 'al');
      },
      variant: TargetPlatformVariant.desktop(),
    );
  });

  group('#603 Rating search: the ✕ belongs to the field', () {
    testWidgets("the ✕ is the search field's suffix icon", (tester) async {
      await _pumpRating(tester);
      expect(find.byIcon(Icons.clear_rounded), findsNothing);

      await tester.enterText(find.byType(TextField), 'jas');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.suffixIcon, isA<IconButton>());
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byIcon(Icons.clear_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'guard: Close keeps the text input connection open',
      (tester) async {
        await _pumpRating(tester);
        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();
        tester.testTextInput.log.clear();

        await tester.tap(
          find.byIcon(Icons.clear_rounded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump();

        expect(
          [for (final c in tester.testTextInput.log) c.method],
          isNot(contains('TextInput.clearClient')),
        );
        expect(_fieldHasFocus(tester), isTrue);
      },
      variant: TargetPlatformVariant.desktop(),
    );
  });
}
