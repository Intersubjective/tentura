// Issue #501: the person-forward page lists both Requests and Posts, so its
// title and the profile action that opens it must not call everything a
// request; neither may the mutual-visibility line on a profile.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _NoPopRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

Future<void> _pumpLoadingPage(WidgetTester tester, Locale locale) async {
  final cubit = PersonForwardCubit(
    personId: 'U-target',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  // Initial state: still loading, no person yet.
  expect(cubit.state.person, isNull);
  final router = _NoPopRouter();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: TenturaResponsiveScope(
            child: BlocProvider<PersonForwardCubit>.value(
              value: cubit,
              child: const PersonForwardPage(),
            ),
          ),
        ),
      ),
    ),
  );
  // A spinner is showing: no pumpAndSettle.
  await tester.pump();
}

Finder _topBarText(bool Function(String text) test) => find.descendant(
  of: find.byType(TenturaTopBar),
  matching: find.byWidgetPredicate(
    (w) => w is Text && test(w.data ?? w.textSpan?.toPlainText() ?? ''),
  ),
);

final _requestWord = RegExp(r'\brequests?\b', caseSensitive: false);

void main() {
  group('person-forward page title before the person loads (#501)', () {
    testWidgets('does not call the item a request', (tester) async {
      await _pumpLoadingPage(tester, const Locale('en'));
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.forwardBeaconTitle), findsNothing);
      expect(_topBarText(_requestWord.hasMatch), findsNothing);
      expect(
        _topBarText((t) => t.toLowerCase().contains('forward')),
        findsOneWidget,
      );
    });

    testWidgets('Russian: no «запрос» in the title', (tester) async {
      await _pumpLoadingPage(tester, const Locale('ru'));

      expect(
        _topBarText((t) => t.toLowerCase().contains('запрос')),
        findsNothing,
      );
      expect(
        _topBarText((t) => t.toLowerCase().contains('пересла')),
        findsOneWidget,
      );
    });
  });

  group('kind-neutral forwarding copy (#501)', () {
    for (final locale in L10n.supportedLocales) {
      test('${locale.languageCode}: the open-eye line names no request', () {
        final l10n = lookupL10n(locale);
        expect(l10n.profileEyeOpen, isNot(matches(_requestWord)));
        expect(
          l10n.profileEyeOpen.toLowerCase(),
          isNot(contains('запрос')),
        );
      });

      test('${locale.languageCode}: the forward action label names no '
          'request', () {
        final l10n = lookupL10n(locale);
        expect(l10n.labelForward, isNot(matches(_requestWord)));
        expect(
          l10n.labelForward.toLowerCase(),
          isNot(contains('запрос')),
        );
      });
    }
  });
}
