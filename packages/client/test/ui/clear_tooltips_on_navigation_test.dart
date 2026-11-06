// #1049: tooltips stay visible when a route covers their anchor; the same
// observer that clears snack bars on navigation dismisses every [Tooltip].
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../support/phone_surface.dart';

final class _FakeRouteMatch extends Fake implements RouteMatch<Object?> {}

TabPageRoute _tab(int index) =>
    TabPageRoute(routeInfo: _FakeRouteMatch(), index: index);

void main() {
  testWidgets(
    'push dismisses visible tooltip — 375×667 RU, long constellation hint',
    (tester) async {
      await usePhoneSurface(tester);
      final hint = lookupL10n(
        const Locale('ru'),
      ).constellationShowDegreeSecondHint;

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          navigatorObservers: [ClearSnackBarsOnPushObserver()],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: hint,
                      child: FilterChip(
                        label: Text(hint, maxLines: 3),
                        onSelected: (_) {},
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('pushed')),
                              body: const Center(child: Text('inner')),
                            ),
                          ),
                        );
                      },
                      child: const Text('Push'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.byType(FilterChip));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsWidgets);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      expect(find.text(hint), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pop dismisses visible tooltip', (tester) async {
    final hint = lookupL10n(
      const Locale('ru'),
    ).constellationShowDegreeSecondHint;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        navigatorObservers: [ClearSnackBarsOnPushObserver()],
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (innerContext) => Scaffold(
                        body: Center(
                          child: Tooltip(
                            message: hint,
                            child: FilterChip(
                              label: const Text('chip'),
                              onSelected: (_) {},
                            ),
                          ),
                        ),
                        floatingActionButton: FloatingActionButton(
                          onPressed: () => Navigator.of(innerContext).pop(),
                          child: const Icon(Icons.arrow_back),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsWidgets);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(hint), findsNothing);
  });

  testWidgets('Home tab change dismisses visible tooltip', (tester) async {
    final hint = lookupL10n(
      const Locale('ru'),
    ).constellationShowDegreeSecondHint;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: Tooltip(
            message: hint,
            child: FilterChip(
              label: const Text('chip'),
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);

    ClearSnackBarsOnPushObserver().didChangeTabRoute(_tab(1), _tab(4));
    await tester.pumpAndSettle();

    expect(find.text(hint), findsNothing);
  });

  testWidgets('mouse hover tooltip is dismissed on push', (tester) async {
    const hint = 'Hover-dismiss probe';
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        navigatorObservers: [ClearSnackBarsOnPushObserver()],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Tooltip(
                    message: hint,
                    child: SizedBox(
                      width: 80,
                      height: 48,
                      child: Placeholder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(body: Text('p2')),
                        ),
                      );
                    },
                    child: const Text('Push'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(Placeholder)));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
  });
}
