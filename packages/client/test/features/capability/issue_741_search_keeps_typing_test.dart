import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/capability/ui/widget/capability_search_field.dart';
import 'package:tentura/features/profile_view/ui/dialog/edit_capabilities_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/util/capability_tag_presenter.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

// #741 (ichorid 2026-11-02): typing was still lost after the search's clear ×
// in the Requirements sheet and in Edit labels. Inside CapabilitySearchField,
// so both screens get it:
// 1. the × stays mounted, disabled, while the field is empty (a pointer left
//    on it keeps its tooltip and the typing focus);
// 2. the field is its own semantics node (Semantics(container: true)).
// Each screen: type, clear via ×, type again with no click on the field →
// the field keeps focus and the query filters the chips. 375×667 and desktop,
// RU and EN.

const _sizes = {'375x667': Size(375, 667), 'desktop': Size(1280, 800)};
const _locales = [Locale('ru'), Locale('en')];
const _semanticsKey = Key('Capability.SearchField.Semantics');
const _rowKey = Key('BeaconCreate.RequirementsRow');

Finder _chip(CapabilityTag tag) =>
    find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug)));

Finder _field() => find.byKey(CapabilitySearchField.fieldKey);

bool _fieldHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _field(), matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

IconButton _clearButton(WidgetTester tester, String clear) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(clear),
        matching: find.byType(IconButton),
      ),
    );

Widget _app(Locale locale, Widget body) => MaterialApp(
  builder: (_, child) => TenturaResponsiveScope(child: child!),
  locale: locale,
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: Scaffold(body: body),
);

Future<void> _useSize(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Type, clear via ×, type again without touching the field.
Future<void> _typeClearType(
  WidgetTester tester, {
  required L10n l10n,
  required PointerDeviceKind pointer,
}) async {
  final clear = l10n.capabilitySearchClear;

  // Empty: the × is there, disabled, with its label.
  expect(find.byTooltip(clear), findsOneWidget);
  expect(_clearButton(tester, clear).onPressed, isNull);

  await tester.showKeyboard(_field());
  tester.testTextInput.enterText(CapabilityTag.calls.labelOf(l10n));
  await tester.pumpAndSettle();
  expect(_chip(CapabilityTag.calls), findsOneWidget);
  expect(_chip(CapabilityTag.transport), findsNothing);
  expect(_clearButton(tester, clear).onPressed, isNotNull);

  await tester.tap(find.byTooltip(clear), kind: pointer);
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(_field()).controller!.text, isEmpty);
  // Still mounted, now disabled; the field still has the typing focus.
  expect(find.byTooltip(clear), findsOneWidget);
  expect(_clearButton(tester, clear).onPressed, isNull);
  expect(_fieldHasFocus(tester), isTrue);

  // Typing again reaches the field with no click on it.
  tester.testTextInput.enterText(CapabilityTag.money.labelOf(l10n));
  await tester.pumpAndSettle();
  expect(_fieldHasFocus(tester), isTrue);
  expect(
    tester.widget<TextField>(_field()).controller!.text,
    CapabilityTag.money.labelOf(l10n),
  );
  expect(_chip(CapabilityTag.money), findsOneWidget);
  expect(_chip(CapabilityTag.transport), findsNothing);
  expect(tester.takeException(), isNull);
}

void _expectOwnSemanticsNode(WidgetTester tester, L10n l10n) {
  final container = find.byKey(_semanticsKey);
  expect(container, findsOneWidget);
  expect(tester.widget<Semantics>(container).container, isTrue);
  expect(find.descendant(of: container, matching: _field()), findsOneWidget);
  // The field's node sits under the container's own node, with the × beside.
  final node = tester.getSemantics(container);
  final flags = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    flags.add(n);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(node);
  expect(
    flags.where((n) => n.getSemanticsData().flagsCollection.isTextField),
    hasLength(1),
  );
  expect(
    flags.where(
      (n) => n.getSemanticsData().tooltip == l10n.capabilitySearchClear,
    ),
    hasLength(1),
  );
}

void main() {
  group('Requirements sheet', () {
    late BeaconCreateCubit cubit;

    setUp(() {
      GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
      cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(),
        effects: FakeUiEffectPort(),
      );
    });

    tearDown(() async {
      await cubit.close();
      await GetIt.I.reset();
    });

    Future<void> open(WidgetTester tester, Locale locale, Size size) async {
      await _useSize(tester, size);
      await tester.pumpWidget(
        _app(
          locale,
          BlocProvider<BeaconCreateCubit>.value(
            value: cubit,
            child: const Form(child: InfoTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_rowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_rowKey));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    }

    for (final locale in _locales) {
      for (final size in _sizes.entries) {
        final l10n = lookupL10n(locale);
        final tag = '${locale.languageCode} ${size.key}';
        final pointer = size.key == 'desktop'
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch;

        testWidgets('$tag: type, clear via ×, type again keeps focus and '
            'filters', (tester) async {
          final semantics = tester.ensureSemantics();
          await open(tester, locale, size.value);
          await _typeClearType(tester, l10n: l10n, pointer: pointer);
          semantics.dispose();
        });

        testWidgets('$tag: the search is its own semantics node', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          await open(tester, locale, size.value);
          _expectOwnSemanticsNode(tester, l10n);
          semantics.dispose();
        });
      }
    }
  });

  group('Edit labels', () {
    Future<void> open(WidgetTester tester, Locale locale, Size size) async {
      await _useSize(tester, size);
      await tester.pumpWidget(
        _app(
          locale,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => EditCapabilitiesDialog.show(
                context,
                subjectId: 'U1',
                subjectName: 'Alice',
                currentVisible: const [],
                onSaved: (_, _) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    for (final locale in _locales) {
      for (final size in _sizes.entries) {
        final l10n = lookupL10n(locale);
        final tag = '${locale.languageCode} ${size.key}';
        final pointer = size.key == 'desktop'
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch;

        testWidgets('$tag: type, clear via ×, type again keeps focus and '
            'filters', (tester) async {
          final semantics = tester.ensureSemantics();
          await open(tester, locale, size.value);
          await _typeClearType(tester, l10n: l10n, pointer: pointer);
          semantics.dispose();
        });

        testWidgets('$tag: the search is its own semantics node', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          await open(tester, locale, size.value);
          _expectOwnSemanticsNode(tester, l10n);
          semantics.dispose();
        });
      }
    }
  });
}
