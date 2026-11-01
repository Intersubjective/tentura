// #605 (#406 on the person forward screen): after Send, the «Запрос
// отправлен: …» bar covered the screen's own «Создать новый запрос для …»
// CTA at the end of the list, which could not be scrolled clear, and on
// desktop the taller error bar covered Send. Both actions now sit in a
// SnackBarClearance, so every bar floats above them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../../ui/snack_bar_clearance_support.dart';

final _bodyKey = GlobalKey(debugLabel: 'person forward body');

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
  }
  final cubit = PersonForwardCubit(
    personId: 'U-target',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  final screen = ScreenCubit(FakeUiEffectPort());
  addTearDown(screen.close);
  cubit.emit(
    PersonForwardState(
      personId: 'U-target',
      person: const Profile(
        id: 'U-target',
        displayName: 'Q1031 Frank',
        score: 1,
        rScore: 1,
      ),
      rows: [
        for (var i = 0; i < 10; i++)
          PersonForwardRow(
            beacon: Beacon.empty.copyWith(
              id: 'B$i',
              title: 'Request $i',
              author: const Profile(id: 'U-me'),
            ),
            involvement: CandidateInvolvement.unseen,
          ),
      ],
      selectedBeaconId: 'B0',
      status: const StateIsSuccess(),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: snackbarKey,
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PersonForwardCubit>.value(value: cubit),
            BlocProvider<ScreenCubit>.value(value: screen),
          ],
          child: Scaffold(
            key: _bodyKey,
            body: BlocBuilder<PersonForwardCubit, PersonForwardState>(
              builder: (context, state) =>
                  personForwardBodyForTest(state: state),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // QA's repro scrolls to the end of the list, where the CTA was.
  final list = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  list.position.jumpTo(list.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<void> _showBar(
  WidgetTester tester,
  String text, {
  bool isError = false,
}) async {
  showSnackBar(
    tester.element(find.byKey(_bodyKey)),
    text: text,
    isError: isError,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

void main() {
  testWidgets('375×667 RU: «Запрос отправлен» clears Send and the '
      '«Создать новый запрос для …» CTA', (tester) async {
    await _pump(tester, size: const Size(375, 667), locale: const Locale('ru'));
    final l10n = lookupL10n(const Locale('ru'));
    const message = 'Запрос отправлен: Q1031 Frank';
    await _showBar(tester, message);

    expectSnackBarClearsButton(
      tester,
      message: message,
      button: find.widgetWithText(
        TextButton,
        l10n.beaconForwardPersonNewRequest('Q1031 Frank'),
      ),
    );
    expectSnackBarClearsButton(
      tester,
      message: message,
      button: find.widgetWithText(FilledButton, l10n.beaconForwardPersonSend),
    );
  });

  testWidgets('desktop: the taller error bar clears Send', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('en'),
    );
    final l10n = lookupL10n(const Locale('en'));
    const message =
        'Could not send the request to Q1031 Frank. Check your connection '
        'and try again.';
    await _showBar(tester, message, isError: true);

    expectSnackBarClearsButton(
      tester,
      message: message,
      button: find.widgetWithText(FilledButton, l10n.beaconForwardPersonSend),
    );
    expectSnackBarClearsButton(
      tester,
      message: message,
      button: find.widgetWithText(
        TextButton,
        l10n.beaconForwardPersonNewRequest('Q1031 Frank'),
      ),
    );
  });
}
