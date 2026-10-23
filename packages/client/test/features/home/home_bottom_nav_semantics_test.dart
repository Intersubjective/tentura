// #668: on phones each bottom-bar tab was announced as its label three times
// ("Requests\nRequests\nRequests": the tile's own label, the visible Text and
// the Tooltip) and never said its position, while the desktop rail says
// "Requests\nTab 1 of 5".
//
// Spec: every bottom-bar tab is ONE button announced once, with its position
// in the same words the rail uses, and no duplicate tooltip.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _labels = ['Requests', 'Posts', 'Activity', 'Field', 'People'];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

HomeBottomNavigationBar _bar({
  int? selectedIndex = 0,
  List<HomeNavDestination>? destinations,
}) => HomeBottomNavigationBar(
  selectedIndex: selectedIndex,
  onDestinationSelected: (_) {},
  destinations:
      destinations ??
      [
        for (final label in _labels)
          HomeNavDestination(
            icon: const Icon(Icons.circle_outlined),
            selectedIcon: const Icon(Icons.circle),
            label: label,
          ),
      ],
);

SemanticsData _tile(WidgetTester tester, String label) =>
    tester.getSemantics(find.text(label)).getSemanticsData();

void main() {
  testWidgets('#668 each bottom-bar tab is announced once with its position', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _bar());

    for (var i = 0; i < _labels.length; i++) {
      final data = _tile(tester, _labels[i]);
      expect(
        data.label,
        '${_labels[i]}\nTab ${i + 1} of ${_labels.length}',
        reason: _labels[i],
      );
      expect(data.tooltip, isEmpty, reason: '${_labels[i]}: no tooltip echo');
    }
    semantics.dispose();
  });

  testWidgets('#668 bottom-bar tab reads the same as the desktop rail tab', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      NavigationRail(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final label in _labels)
            NavigationRailDestination(
              icon: const Icon(Icons.circle_outlined),
              label: Text(label),
            ),
        ],
      ),
    );
    final rail = [for (final l in _labels) _tile(tester, l).label];

    await _pump(tester, _bar());
    final bar = [for (final l in _labels) _tile(tester, l).label];

    expect(bar, rail);
    semantics.dispose();
  });

  testWidgets('#668 the position follows the app locale', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _bar(), locale: const Locale('ru'));

    final position = MaterialLocalizations.of(
      tester.element(find.text('Posts')),
    ).tabLabel(tabIndex: 2, tabCount: 5);
    expect(position, isNot(contains('Tab')));
    expect(_tile(tester, 'Posts').label, 'Posts\n$position');
    semantics.dispose();
  });

  testWidgets('#668 a label-less tab is announced by its tooltip once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _bar(
        destinations: const [
          HomeNavDestination(
            icon: Icon(Icons.circle_outlined),
            selectedIcon: Icon(Icons.circle),
            label: 'Requests',
          ),
          HomeNavDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: '',
            tooltip: 'Field',
            commandChrome: true,
          ),
        ],
      ),
    );

    final field = tester
        .getSemantics(find.byIcon(Icons.hub_outlined))
        .getSemanticsData();
    expect(field.label, 'Field\nTab 2 of 2');
    expect(field.tooltip, isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'guard: tabs stay tappable buttons and only the open one is selected',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _bar(selectedIndex: 1));

      for (var i = 0; i < _labels.length; i++) {
        final data = _tile(tester, _labels[i]);
        expect(data.flagsCollection.isButton, isTrue, reason: _labels[i]);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: _labels[i]);
        expect(
          data.flagsCollection.isSelected == Tristate.isTrue,
          i == 1,
          reason: _labels[i],
        );
      }
      semantics.dispose();
    },
  );
}
