// #782: RU Settings language/theme segments must not break words mid-word at 375 px.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/settings/ui/widget/language_switch_button.dart';
import 'package:tentura/features/settings/ui/widget/theme_switch_button.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(
    localePreference: kLocalePreferenceRu,
    themeMode: ThemeMode.system,
  );

  @override
  Stream<SettingsState> get stream => Stream<SettingsState>.value(state);
}

void _expectOneWholeLine(WidgetTester tester, String label) {
  final finder = find.text(label);
  expect(finder, findsOneWidget, reason: label);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.constraints.maxWidth);
  addTearDown(painter.dispose);
  expect(
    painter.computeLineMetrics().length,
    1,
    reason: '$label should stay on one line at 375 px',
  );
  expect(paragraph.didExceedMaxLines, isFalse);
}

void main() {
  testWidgets('RU 375×667: settings segment labels stay on one line', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    GetIt.I.registerSingleton<SettingsCubit>(_FakeSettingsCubit());
    addTearDown(() => GetIt.I.unregister<SettingsCubit>());

    final ru = lookupL10n(const Locale('ru'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: kPhoneSurface),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(
                  TenturaTheme.light()
                      .extension<TenturaTokens>()!
                      .screenHPadding,
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LanguageSwitchButton(),
                    SizedBox(height: 16),
                    ThemeSwitchButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      ru.languageSystem,
      ru.system,
      ru.light,
      ru.dark,
    ]) {
      _expectOneWholeLine(tester, label);
    }
    expect(tester.takeException(), isNull);
  });
}
