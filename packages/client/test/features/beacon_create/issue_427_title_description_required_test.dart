// #427: the Request editor title and description fields must read as one
// form: the same outlined style with a floating label, and both marked
// as required (the editor refuses to publish without either).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

/// The words the floating label shows, however the field builds it
/// (`labelText` or a `label` widget).
String fieldLabelOf(WidgetTester tester, String testId) {
  final decorator = tester.widget<InputDecorator>(
    find.descendant(
      of: find.byKey(TestIds.key(testId)),
      matching: find.byType(InputDecorator),
    ),
  );
  final d = decorator.decoration;
  final text = d.labelText;
  if (text != null) return text;
  final label = d.label;
  if (label is Text) return label.data ?? label.textSpan?.toPlainText() ?? '';
  if (label is RichText) return label.text.toPlainText();
  return '';
}

InputDecoration fieldDecorationOf(WidgetTester tester, String testId) => tester
    .widget<InputDecorator>(
      find.descendant(
        of: find.byKey(TestIds.key(testId)),
        matching: find.byType(InputDecorator),
      ),
    )
    .decoration;

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
    if (GetIt.I.isRegistered<Env>()) {
      await GetIt.I.unregister<Env>();
    }
  });

  Future<void> pumpInfoTab(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
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
      ),
    );
    await tester.pumpAndSettle();
  }

  const fields = [TestIds.requestTitle, TestIds.requestDescription];

  for (final (locale, marker) in const [
    (Locale('en'), '(required)'),
    (Locale('ru'), '(обязательно)'),
  ]) {
    final lang = locale.languageCode;
    testWidgets(
      'title and description labels are marked required ($lang)',
      (tester) async {
        await pumpInfoTab(tester, locale);
        for (final id in fields) {
          final label = fieldLabelOf(tester, id);
          expect(label, contains(marker), reason: '$id label: "$label"');
          // Marked once, and the label still names the field.
          expect(marker.allMatches(label).length, 1, reason: label);
          expect(
            label.replaceAll(marker, '').trim(),
            isNotEmpty,
            reason: '$id label is only the marker',
          );
        }
        // Two fields, two different labels.
        expect(
          fieldLabelOf(tester, TestIds.requestTitle),
          isNot(fieldLabelOf(tester, TestIds.requestDescription)),
        );
      },
    );
  }

  testWidgets('title and description share one outlined, labelled style', (
    tester,
  ) async {
    await pumpInfoTab(tester, const Locale('en'));
    final title = fieldDecorationOf(tester, TestIds.requestTitle);
    final description = fieldDecorationOf(tester, TestIds.requestDescription);
    for (final d in [title, description]) {
      expect(d.enabledBorder, isA<OutlineInputBorder>());
      expect(d.filled, isTrue);
    }
    expect(description.enabledBorder, title.enabledBorder);
    expect(description.focusedBorder, title.focusedBorder);
    expect(description.fillColor, title.fillColor);
    expect(description.labelStyle, title.labelStyle);
    // A label, not a placeholder standing in for one.
    expect(fieldLabelOf(tester, TestIds.requestTitle), isNotEmpty);
    expect(fieldLabelOf(tester, TestIds.requestDescription), isNotEmpty);
  });
}
