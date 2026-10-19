import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

// #434: in the When? sheet the segment in use was a pale tint while the
// others stayed white, so a white segment read as the chosen one; and the
// date row ("Tap to choose") was not a button for assistive tech.

Widget _infoTabHarness(BeaconCreateCubit cubit) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(800, 1200)),
    child: Scaffold(
      body: BlocProvider<BeaconCreateCubit>.value(
        value: cubit,
        child: const Form(child: InfoTab()),
      ),
    ),
  ),
);

Finder _segmentedButton() => find.byType(SegmentedButton<BeaconScheduleKind>);

/// The `TextButton` that renders the segment labelled [label].
Finder _segment(String label) => find.ancestor(
  of: find.descendant(of: _segmentedButton(), matching: find.text(label)),
  matching: find.byType(TextButton),
);

/// Fill colour the segment paints (the button's own `Material`).
Color? _segmentFill(WidgetTester tester, String label) => tester
    .widget<Material>(
      find
          .descendant(of: _segment(label), matching: find.byType(Material))
          .first,
    )
    .color;

/// Colour the segment's label text is painted in.
Color? _segmentLabelColor(WidgetTester tester, String label) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: _segmentedButton(), matching: find.text(label)),
    )
    .text
    .style
    ?.color;

/// Number of icons (the check mark) drawn inside the segment.
int _segmentIcons(String label) => find
    .descendant(of: _segment(label), matching: find.byType(Icon))
    .evaluate()
    .length;

/// Everything a screen reader announces for [data].
String _spoken(SemanticsData data) =>
    [data.label, data.value, data.hint, data.tooltip].join(' ');

/// Engine-visible (not merged-up) tappable button nodes whose announcement
/// contains every piece of [parts].
SemanticsFinder _buttonNodeSaying(List<String> parts) =>
    find.semantics.byPredicate((node) {
      if (node.isMergedIntoParent) return false;
      final data = node.getSemanticsData();
      final spoken = _spoken(data);
      return data.flagsCollection.isButton &&
          data.hasAction(SemanticsAction.tap) &&
          parts.every(spoken.contains);
    });

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
  });

  tearDown(() async {
    await cubit.close();
    await GetIt.I.reset();
  });

  Future<void> openWhenSheet(WidgetTester tester) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('BeaconCreate.TimingRow')));
    await tester.tap(find.byKey(const Key('BeaconCreate.TimingRow')));
    await tester.pumpAndSettle();
    expect(_segmentedButton(), findsOneWidget);
  }

  group('When? sheet segmented control shows the choice clearly (#434)', () {
    testWidgets('the segment in use is filled with the primary colour and '
        'the others are not', (tester) async {
      await openWhenSheet(tester);
      final scheme = Theme.of(tester.element(_segmentedButton())).colorScheme;

      // A new Request has no date: "No date" is the segment in use.
      expect(_segmentFill(tester, 'No date'), scheme.primary);
      expect(_segmentLabelColor(tester, 'No date'), scheme.onPrimary);
      for (final other in ['Deadline', 'Date / period']) {
        expect(
          _segmentFill(tester, other),
          anyOf(isNull, Colors.transparent),
          reason: '"$other" is not in use and must not look filled',
        );
      }

      // The fill follows the choice.
      await tester.tap(
        find.descendant(
          of: _segmentedButton(),
          matching: find.text('Deadline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_segmentFill(tester, 'Deadline'), scheme.primary);
      expect(_segmentLabelColor(tester, 'Deadline'), scheme.onPrimary);
      expect(
        _segmentFill(tester, 'No date'),
        anyOf(isNull, Colors.transparent),
      );
    });

    testWidgets('only the segment in use carries a check mark', (tester) async {
      await openWhenSheet(tester);

      expect(_segmentIcons('No date'), 1);
      expect(_segmentIcons('Deadline'), 0);
      expect(_segmentIcons('Date / period'), 0);

      await tester.tap(
        find.descendant(
          of: _segmentedButton(),
          matching: find.text('Date / period'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_segmentIcons('Date / period'), 1);
      expect(_segmentIcons('No date'), 0);
      expect(_segmentIcons('Deadline'), 0);
    });
  });

  group('When? sheet date row is a labelled button (#434)', () {
    testWidgets('with no date yet the row is a button that names the mode and '
        'says Tap to choose, and a semantics tap opens the date picker', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openWhenSheet(tester);
      await tester.tap(
        find.descendant(
          of: _segmentedButton(),
          matching: find.text('Deadline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('BeaconCreate.TimingField')), findsOneWidget);

      final row = _buttonNodeSaying(['Deadline', 'Tap to choose']);
      expect(row.evaluate(), hasLength(1));

      tester.semantics.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('with a date set the row is a button announcing the mode and '
        'the chosen date', (tester) async {
      final semantics = tester.ensureSemantics();
      cubit.setDeadline(DateTime(2030, 1, 15));
      await openWhenSheet(tester);

      // Raw precondition: the sheet opened on Deadline with a date shown.
      final shown = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('BeaconCreate.TimingField')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty && s != 'Tap to choose')
          .toList();
      expect(shown, hasLength(1));
      expect(shown.single, contains('15'));

      final row = _buttonNodeSaying(['Deadline', shown.single]);
      expect(row.evaluate(), hasLength(1));
      semantics.dispose();
    });

    testWidgets('the date row is not announced as the When? title or as a '
        'segment', (tester) async {
      // Negative guard: a fix that turns the whole sheet (title, segments and
      // row) into one merged button would make the segments unreachable.
      final semantics = tester.ensureSemantics();
      await openWhenSheet(tester);
      await tester.tap(
        find.descendant(
          of: _segmentedButton(),
          matching: find.text('Deadline'),
        ),
      );
      await tester.pumpAndSettle();

      final row = _buttonNodeSaying(['Deadline', 'Tap to choose']);
      expect(row.evaluate(), hasLength(1));
      final spoken = _spoken(row.evaluate().single.getSemanticsData());
      expect(spoken, isNot(contains('When?')));
      expect(spoken, isNot(contains('Date / period')));
      expect(spoken, isNot(contains('No date')));
      semantics.dispose();
    });
  });
}
