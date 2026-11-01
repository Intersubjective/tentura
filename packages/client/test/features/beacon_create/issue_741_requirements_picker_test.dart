import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/info_tab.dart';
import 'package:tentura/features/capability/ui/widget/capability_search_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

// #741 (QA run 2), the Requirements picker in the request editor:
// 1. the first tap on «Requirements» looked dead while the draft was being
//    saved (the sheet waited for the server), so it took a second tap;
// 2. it opened on a bare list of folded categories: now the first group
//    starts open;
// 3. there was no search: a search box filters the groups and opens every
//    matching one.
// Each runs in EN and RU, on a 375×667 phone and at desktop width.

const _sizes = {'375x667': Size(375, 667), 'desktop': Size(1280, 800)};
const _locales = [Locale('en'), Locale('ru')];

const _rowKey = Key('BeaconCreate.RequirementsRow');

Finder _sheet() => find.byType(DraggableScrollableSheet);

Finder _inSheet(Finder finder) =>
    find.descendant(of: _sheet(), matching: finder);

Finder _chip(CapabilityTag tag) =>
    _inSheet(find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug))));

void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
  });

  tearDown(() async {
    await cubit.close();
    await GetIt.I.reset();
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Locale locale,
    required Size size,
    FakeBeaconWritePort? write,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: BlocProvider<BeaconCreateCubit>.value(
            value: cubit,
            child: const Form(child: InfoTab()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_rowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_rowKey));
    await tester.pumpAndSettle();
    expect(_sheet(), findsOneWidget);
  }

  for (final locale in _locales) {
    for (final size in _sizes.entries) {
      final tag = '${locale.languageCode} ${size.key}';
      final l10n = lookupL10n(locale);

      testWidgets('$tag: one tap opens the sheet with the title focused and '
          'the draft save still out', (tester) async {
        // A title and description make the tap flush the draft, and the
        // first save creates it on the (held) server.
        final write = FakeBeaconWritePort()..createHold = Completer<void>();
        cubit =
            BeaconCreateCubit(
                beaconCreateCase: fakeBeaconCreateCase(write: write),
                effects: FakeUiEffectPort(),
              )
              ..setTitle('Need a piano moved')
              ..setDescription('Two flights of stairs, this weekend.');
        await pumpEditor(tester, locale: locale, size: size.value);

        final title = find.byKey(TestIds.key(TestIds.requestTitle));
        await tester.showKeyboard(title);
        await tester.pump();
        final editable = find.descendant(
          of: title,
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isTrue,
        );

        await tester.ensureVisible(find.byKey(_rowKey));
        await tester.pump();
        await tester.tap(find.byKey(_rowKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(_sheet(), findsOneWidget);

        write.createHold!.complete();
        await tester.pumpAndSettle();
        expect(_sheet(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$tag: nothing chosen, the first group opens with its '
          'chips', (tester) async {
        cubit = BeaconCreateCubit(
          beaconCreateCase: fakeBeaconCreateCase(),
          effects: FakeUiEffectPort(),
        );
        await pumpEditor(tester, locale: locale, size: size.value);
        await openSheet(tester);

        expect(_chip(CapabilityTag.transport), findsOneWidget);
        expect(_chip(CapabilityTag.tools), findsOneWidget);
        // Accordion: the other groups stay folded.
        expect(_chip(CapabilityTag.calls), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$tag: search filters the chips and opens the matching '
          'group', (tester) async {
        cubit = BeaconCreateCubit(
          beaconCreateCase: fakeBeaconCreateCase(),
          effects: FakeUiEffectPort(),
        );
        await pumpEditor(tester, locale: locale, size: size.value);
        await openSheet(tester);

        final search = _inSheet(find.byKey(CapabilitySearchField.fieldKey));
        expect(search, findsOneWidget);

        // «Calls» is not in the first group: the match opens its group.
        await tester.enterText(search, CapabilityTag.calls.labelOf(l10n));
        await tester.pumpAndSettle();
        expect(_chip(CapabilityTag.calls), findsOneWidget);
        expect(_chip(CapabilityTag.transport), findsNothing);
        expect(
          _inSheet(find.byType(FilterChip)).evaluate().length,
          lessThan(CapabilityTag.values.length),
        );

        await tester.enterText(search, 'zzqxw');
        await tester.pumpAndSettle();
        expect(_inSheet(find.byType(FilterChip)), findsNothing);
        expect(_inSheet(find.text(l10n.capabilitySearchEmpty)), findsOneWidget);

        // Cleared, the picker is back to its first view.
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        expect(_chip(CapabilityTag.transport), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
