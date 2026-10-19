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

/// #397 residual: the request editor clamps a paste that runs past the
/// title/description cap, but said nothing, so the user did not know the
/// end of their text was gone. A short notice must say it was shortened,
/// and only when something was actually cut.
void main() {
  late BeaconCreateCubit cubit;
  final l10n = lookupL10n(const Locale('en'));

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

  // Inline text and a SnackBar both build within these frames.
  Future<void> settleNotice(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a pasted description past the cap shows a shortened notice', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconCreateTextShortenedNotice), findsNothing);

    // 1 500 emoji: 3 000 UTF-16 code units, clamped to 2 048.
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestDescription)),
      '🙂' * 1500,
    );
    await settleNotice(tester);

    expect(cubit.state.description.length, kBeaconDescriptionMaxLength);
    expect(find.text(l10n.beaconCreateTextShortenedNotice), findsOneWidget);
  });

  testWidgets('the shortened notice does not stick after a short edit', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    final description = find.byKey(TestIds.key(TestIds.requestDescription));
    await tester.enterText(description, '🙂' * 1500);
    await settleNotice(tester);
    expect(find.text(l10n.beaconCreateTextShortenedNotice), findsOneWidget);

    // The user rewrites it short: nothing is cut any more.
    await tester.enterText(description, 'Short now');
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    // Lets a SnackBar that timed out finish its exit animation.
    await tester.pump(const Duration(seconds: 1));

    expect(cubit.state.description, 'Short now');
    expect(find.text(l10n.beaconCreateTextShortenedNotice), findsNothing);
  });

  testWidgets('a pasted title past the cap shows a shortened notice', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    // 64 code units of plain words: cut mid-word at 60.
    const pasted =
        'Need help moving a heavy sofa up to the fourth floor this Sunday';
    expect(pasted.length, greaterThan(kBeaconTitleMaxLength));
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestTitle)),
      pasted,
    );
    await settleNotice(tester);

    expect(cubit.state.title, pasted.substring(0, kBeaconTitleMaxLength));
    expect(find.text(l10n.beaconCreateTextShortenedNotice), findsOneWidget);
  });

  testWidgets('text that fits exactly or under the cap shows no notice', (
    tester,
  ) async {
    await tester.pumpWidget(_infoTabHarness(cubit));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestTitle)),
      'Help me move 📦',
    );
    // 1 024 emoji: exactly 2 048 code units, nothing cut.
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestDescription)),
      '🙂' * (kBeaconDescriptionMaxLength ~/ 2),
    );
    await settleNotice(tester);

    expect(cubit.state.description.length, kBeaconDescriptionMaxLength);
    expect(
      find.text('$kBeaconDescriptionMaxLength/$kBeaconDescriptionMaxLength'),
      findsOneWidget,
    );
    expect(find.text(l10n.beaconCreateTextShortenedNotice), findsNothing);
  });
}
