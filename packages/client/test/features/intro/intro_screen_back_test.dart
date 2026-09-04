import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/intro/ui/screen/intro_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state =>
      const SettingsState(visibleVersion: 'test', introEnabled: true);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

void main() {
  late _FakeSettingsCubit settingsCubit;
  var registeredSettings = false;

  setUp(() {
    settingsCubit = _FakeSettingsCubit();
    final getIt = GetIt.I;
    if (!getIt.isRegistered<SettingsCubit>()) {
      getIt.registerSingleton<SettingsCubit>(settingsCubit);
      registeredSettings = true;
    }
  });

  tearDown(() {
    if (registeredSettings && GetIt.I.isRegistered<SettingsCubit>()) {
      GetIt.I.unregister<SettingsCubit>();
    }
    registeredSettings = false;
  });

  Future<void> pumpIntro(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: const IntroScreen(),
      ),
    );
    // Allow PageView + SVG asset decode; settle page animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Back is reserved but not hittable on first slide', (
    tester,
  ) async {
    await pumpIntro(tester);

    expect(find.text('Back'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Back').hitTestable(),
      findsNothing,
    );
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('Next then Back returns to first slide without layout jump', (
    tester,
  ) async {
    await pumpIntro(tester);

    final page1Title = find.text('Get things done through people you trust');
    expect(page1Title, findsOneWidget);

    final backSlot = find.byType(Visibility);
    expect(backSlot, findsOneWidget);
    final sizeOnPage0 = tester.getSize(backSlot);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(
      find.text('Post a request, friends pass it on'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Back').hitTestable(),
      findsOneWidget,
    );
    expect(tester.getSize(backSlot), sizeOnPage0);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(page1Title, findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Back').hitTestable(),
      findsNothing,
    );
  });
}
