import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

const _descriptionRequired = 'Description is required';

Finder _titleField() => find.byKey(TestIds.key(TestIds.requestTitle));

Finder _descriptionField() => find.byKey(TestIds.key(TestIds.requestDescription));

Widget _infoTabHarness(BeaconCreateCubit cubit) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(800, 1200)),
      child: Scaffold(
        body: BlocProvider<BeaconCreateCubit>.value(
          value: cubit,
          child: const Form(
            child: InfoTab(key: ValueKey('BeaconCreate.InfoTab')),
          ),
        ),
      ),
    ),
  );
}

/// GitHub #163 — typing in the request title must not surface description
/// validation until the user has left the description field or tapped Next.
void main() {
  late BeaconCreateCubit cubit;

  setUp(() {
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    GetIt.I.registerSingleton<Env>(
      const Env(googleMapsApiKey: 'test-key'),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (GetIt.I.isRegistered<Env>()) {
      await GetIt.I.unregister<Env>();
    }
  });

  /// Spurious [FocusNode] notifications (e.g. [FocusNode.canRequestFocus]
  /// toggles) call listeners even when the user never focused description.
  /// Current [_InfoTabState._onDescriptionFocusChange] latches
  /// `_descriptionBlurred` on any `!hasFocus` notify — reproduces #163.
  void _spuriousDescriptionFocusNotify(WidgetTester tester) {
    final editable = find.descendant(
      of: _descriptionField(),
      matching: find.byType(EditableText),
    );
    final node = tester.widget<EditableText>(editable).focusNode;
    expect(node.hasFocus, isFalse);
    node.canRequestFocus = false;
    node.canRequestFocus = true;
  }

  group('issue #163 title keystrokes vs description validation', () {
    testWidgets(
      'title typing after spurious description focus notify hides required error',
      (tester) async {
        await tester.pumpWidget(_infoTabHarness(cubit));
        await tester.pumpAndSettle();

        _spuriousDescriptionFocusNotify(tester);
        await tester.pump();

        await tester.tap(_titleField());
        await tester.enterText(_titleField(), 'Need help moving');
        await tester.pump();

        expect(
          find.text(_descriptionRequired),
          findsNothing,
          reason:
              'Description error must not appear when user never touched '
              'description (only spurious FocusNode notify)',
        );
      },
    );

    testWidgets(
      'typing only in title does not show Description is required',
      (tester) async {
        await tester.pumpWidget(_infoTabHarness(cubit));
        await tester.pumpAndSettle();

        expect(find.text(_descriptionRequired), findsNothing);

        await tester.tap(_titleField());
        await tester.pump();

        const title = 'Need help moving';
        final editable = find.descendant(
          of: _titleField(),
          matching: find.byType(EditableText),
        );
        await tester.showKeyboard(editable);
        await tester.pump();

        var partial = '';
        for (final unit in title.runes) {
          partial += String.fromCharCode(unit);
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: partial,
              selection: TextSelection.collapsed(offset: partial.length),
            ),
          );
          await tester.pump();
          expect(
            find.text(_descriptionRequired),
            findsNothing,
            reason:
                'Description error must stay hidden while editing title only '
                '(after IME update "$partial")',
          );
        }

        expect(cubit.state.description.trim(), isEmpty);
        expect(cubit.state.title, 'Need help moving');
      },
    );

    testWidgets(
      'Next with empty description still shows Description is required',
      (tester) async {
        await tester.pumpWidget(_infoTabHarness(cubit));
        await tester.pumpAndSettle();

        await tester.enterText(_titleField(), 'Need help moving');
        await tester.pump();

        cubit.validate();
        cubit.revealValidationHints();
        await tester.pump();

        expect(find.text(_descriptionRequired), findsOneWidget);
      },
    );
  });
}
