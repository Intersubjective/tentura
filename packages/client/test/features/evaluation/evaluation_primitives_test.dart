import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_capability_picker_sheet.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_impact_control.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

Widget _app(
  Widget child, {
  Size size = const Size(375, 800),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme ?? TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: textScaler),
      child: TenturaResponsiveScope(child: child),
    ),
  );
}

void _ignore(EvaluationValue _) {}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _impact(String name) =>
    find.byKey(TestIds.key(TestIds.evaluationImpact(name)));

void main() {
  testWidgets('impact control renders exactly five ordered choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const EvaluationImpactControl(value: null, onChanged: _ignore)),
    );
    const labels = <String>[
      'Helped a lot',
      'Helped somewhat',
      'No real effect',
      'Hurt somewhat',
      'Hurt a lot',
    ];
    for (var i = 0; i < labels.length; i++) {
      expect(find.text(labels[i]), findsOneWidget);
      if (i > 0) {
        expect(
          tester.getTopLeft(find.text(labels[i])).dy,
          greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        );
      }
    }
    expect(find.text('No basis'), findsNothing);
    expect(find.textContaining(RegExp(r'[+-]?\d')), findsNothing);
    expect(
      find.textContaining(RegExp('trust', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('every impact row is at least the Material target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const EvaluationImpactControl(
          value: EvaluationValue.pos1,
          onChanged: _ignore,
        ),
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
      ),
    );
    for (final value in evaluationImpactValues()) {
      expect(
        tester.getSize(_impact(value.name)).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('impact control remains responsive at expanded width', (
    tester,
  ) async {
    _setViewSize(tester, const Size(840, 640));
    await tester.pumpWidget(
      _app(
        const EvaluationImpactControl(
          value: EvaluationValue.neg1,
          onChanged: _ignore,
        ),
        size: const Size(840, 640),
      ),
    );
    final control = find.byType(EvaluationImpactControl);
    expect(tester.getSize(control).width, lessThanOrEqualTo(840));
    expect(tester.takeException(), isNull);
  });

  testWidgets('impact rows are enabled and mutually exclusive in semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const EvaluationImpactControl(
          value: EvaluationValue.pos1,
          onChanged: _ignore,
        ),
      ),
    );
    expect(
      tester.getSemantics(_impact('pos1')),
      matchesSemantics(
        label: 'Helped somewhat',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        isSelected: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      tester.getSemantics(_impact('pos2')),
      matchesSemantics(
        label: 'Helped a lot',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    for (final value in evaluationImpactValues()) {
      final node = tester.getSemantics(_impact(value.name));
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(node.hasFlag(SemanticsFlag.isFocusable), isTrue);
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        node.hasFlag(SemanticsFlag.isSelected),
        value == EvaluationValue.pos1,
      );
    }
    semantics.dispose();
  });

  testWidgets('keyboard traversal starts after an explicit preceding control', (
    tester,
  ) async {
    final activated = <EvaluationValue>[];
    await tester.pumpWidget(
      _app(
        FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            children: [
              ElevatedButton(
                onPressed: () {},
                child: const Text('Before impact'),
              ),
              EvaluationImpactControl(
                value: null,
                onChanged: activated.add,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Before impact'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activated, [EvaluationValue.pos2]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activated, [EvaluationValue.pos2, EvaluationValue.pos1]);
  });

  testWidgets('authorized capability filter keeps a saved stale tag visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: CapabilityChipSet(
            selectedSlugs: const {'tools'},
            availableSlugs: const {'tools'},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Logistics'));
    await tester.pumpAndSettle();
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Transport'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact picker enforces cap before Done and returns canonical order',
    (tester) async {
      Set<String>? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await EvaluationCapabilityPickerSheet.show(
                  context,
                  initialSlugs: const {},
                  availableSlugs: const {
                    'transport',
                    'storage',
                    'pickup_delivery',
                    'tools',
                  },
                  maxSelection: 3,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      await tester.tap(find.text('Logistics'));
      await tester.pumpAndSettle();
      for (final slug in ['transport', 'storage', 'pickup_delivery']) {
        await tester.tap(find.byKey(TestIds.key(TestIds.capabilityChip(slug))));
        await tester.pump();
      }
      final fourth = tester.widget<FilterChip>(
        find.byKey(TestIds.key(TestIds.capabilityChip('tools'))),
      );
      expect(fourth.onSelected, isNull);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.evaluationCapabilityDone)),
      );
      await tester.pumpAndSettle();
      expect(result, ['transport', 'storage', 'pickup_delivery']);
    },
  );

  testWidgets('picker Cancel returns null without changing parent', (
    tester,
  ) async {
    Set<String>? result = const {'parent'};
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await EvaluationCapabilityPickerSheet.show(
                context,
                initialSlugs: const {'tools'},
                availableSlugs: const {'tools'},
                maxSelection: 3,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logistics'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(TestIds.key(TestIds.capabilityChip('tools'))),
          )
          .selected,
      isTrue,
    );
    await tester.tap(
      find.byKey(TestIds.key(TestIds.evaluationCapabilityCancel)),
    );
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('picker back and barrier dismiss return null', (tester) async {
    Set<String>? result = const {'parent'};
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await EvaluationCapabilityPickerSheet.show(
                context,
                initialSlugs: const {'tools'},
                availableSlugs: const {'tools'},
                maxSelection: 3,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(result, isNull);

    result = const {'parent'};
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  for (final size in [const Size(320, 375), const Size(375, 320)]) {
    testWidgets(
      'compact picker remains scrollable at ${size.width}x${size.height} and 200%',
      (tester) async {
        _setViewSize(tester, size);
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => EvaluationCapabilityPickerSheet.show(
                  context,
                  initialSlugs: const {},
                  availableSlugs: Set.from(
                    CapabilityTag.values.map((tag) => tag.slug),
                  ),
                  maxSelection: 3,
                ),
                child: const Text('Open'),
              ),
            ),
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(600, 800), const Size(840, 800)]) {
    testWidgets('regular and expanded picker use a dialog at ${size.width}px', (
      tester,
    ) async {
      _setViewSize(tester, size);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => EvaluationCapabilityPickerSheet.show(
                context,
                initialSlugs: const {'tools'},
                availableSlugs: const {'tools'},
                maxSelection: 3,
              ),
              child: const Text('Open'),
            ),
          ),
          size: size,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('zero cap trims an initial selection so Done remains usable', (
    tester,
  ) async {
    Set<String>? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await EvaluationCapabilityPickerSheet.show(
                context,
                initialSlugs: const {'tools'},
                availableSlugs: const {'tools'},
                maxSelection: 0,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TestIds.key(TestIds.evaluationCapabilityDone)));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
  });

  test('canonical order follows CapabilityTag catalog order', () {
    expect(
      CapabilityTag.values.indexOf(CapabilityTag.transport),
      lessThan(CapabilityTag.values.indexOf(CapabilityTag.tools)),
    );
  });
}
