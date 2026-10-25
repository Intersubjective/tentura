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
// Follow-up (QA 7.50.3): in the browser, with semantics on, the press on ✕
// still moved the browser focus off the field's input to the page while
// Flutter kept the field focused, so the first click back and the keys after
// it were lost (as #688). Spec: the ✕ is tagged so the web keeps the browser
// focus on the field when it is pressed, and if the browser focus has left
// the field anyway, Close (or a click on the field) re-attaches it.
//
// Follow-up (QA 7.50.7): still lost after Close. Close checked the browser
// focus while the ✕ was still on screen; the focus can leave the input in
// the frame that takes the ✕ away. Spec: Close checks again once that frame
// is drawn, and re-attaches the field if the focus has gone by then.

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
import 'package:tentura/ui/test_ids.dart';

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

  group('#603 Rating search: the browser focus stays on the field', () {
    List<String> methodsAfterClose(WidgetTester tester) => [
      for (final c in tester.testTextInput.log) c.method,
    ].skipWhile((m) => m != 'TextInput.clearClient').toList();

    testWidgets('the ✕ is tagged as a press that keeps the field focus', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final kept = <String>[];
        debugRatingKeepTextInputFocusOnPress = kept.addAll;
        addTearDown(() => debugRatingKeepTextInputFocusOnPress = null);
        await _pumpRating(tester);

        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();

        expect(
          find.bySemanticsIdentifier(TestIds.ratingSearchClear),
          findsOneWidget,
        );
        // A press inside this node no longer moves the browser focus.
        expect(
          kept.any(TestIds.ratingSearchClear.startsWith),
          isTrue,
          reason: 'registered prefixes: $kept',
        );
      } finally {
        semantics.dispose();
      }
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

    testWidgets(
      'Close re-attaches the field if the browser took focus',
      (tester) async {
        debugRatingSearchTextInputHasPlatformFocus = () => false;
        addTearDown(() => debugRatingSearchTextInputHasPlatformFocus = null);
        final cubit = await _pumpRating(tester);
        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();
        tester.testTextInput.log.clear();

        await tester.tap(
          find.byIcon(Icons.clear_rounded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump();

        // The field reconnects its text input, the way a click into it does,
        // so the browser puts focus back on its input.
        expect(
          methodsAfterClose(tester),
          containsAllInOrder(['TextInput.setClient', 'TextInput.show']),
        );
        expect(_fieldHasFocus(tester), isTrue);
        tester.testTextInput.enterText('mi');
        await tester.pump();
        expect(_fieldText(tester), 'mi');
        expect(cubit.state.searchFilter, 'mi');
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'Close re-attaches the field if the browser focus goes with the ✕',
      (tester) async {
        // The browser focus is still on the input while the ✕ is pressed
        // and leaves it in the frame that takes the ✕ away (QA 7.50.7).
        debugRatingSearchTextInputHasPlatformFocus = () =>
            find.byIcon(Icons.clear_rounded).evaluate().isNotEmpty;
        addTearDown(() => debugRatingSearchTextInputHasPlatformFocus = null);
        final cubit = await _pumpRating(tester);
        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();
        tester.testTextInput.log.clear();

        await tester.tap(
          find.byIcon(Icons.clear_rounded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.byIcon(Icons.clear_rounded), findsNothing);
        expect(
          methodsAfterClose(tester),
          containsAllInOrder(['TextInput.setClient', 'TextInput.show']),
        );
        expect(_fieldHasFocus(tester), isTrue);
        tester.testTextInput.enterText('mi');
        await tester.pump();
        expect(_fieldText(tester), 'mi');
        expect(cubit.state.searchFilter, 'mi');
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'a click on the focused field re-attaches it if the browser took focus',
      (tester) async {
        final cubit = await _pumpRating(tester);
        await tester.enterText(find.byType(TextField), 'jas');
        await tester.pump();
        debugRatingSearchTextInputHasPlatformFocus = () => false;
        addTearDown(() => debugRatingSearchTextInputHasPlatformFocus = null);
        tester.testTextInput.log.clear();

        await tester.tap(
          find.byType(TextField),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump();

        expect(
          methodsAfterClose(tester),
          containsAllInOrder(['TextInput.setClient', 'TextInput.show']),
        );
        expect(_fieldHasFocus(tester), isTrue);
        tester.testTextInput.enterText('jasp');
        await tester.pump();
        expect(_fieldText(tester), 'jasp');
        expect(cubit.state.searchFilter, 'jasp');
      },
      variant: TargetPlatformVariant.desktop(),
    );
  });
}
