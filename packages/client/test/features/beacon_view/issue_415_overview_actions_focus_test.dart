// #415 (QA r8pr3 residual): in the author's Overview, Tab put Flutter's
// focus on «We have enough help» and then on Forward, but the browser's
// focus stayed both times on the Questions entry above them, so a screen
// reader announced the Questions block twice and never the button. The
// author action names itself with an outer
// `Semantics(label: ..., excludeSemantics: true)`, which also hid the
// button's focus state: no semantics node said it had focus.
//
// Spec: Questions is one Tab stop; «We have enough help» and Forward are
// stops of their own, each putting the focus on its own node.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_action_button.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_act_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/a11y_tab_walk.dart';
import '../beacon_lobby/fake_lobby_port.dart';

const _before = 'Control before';
const _after = 'Control after';

BeaconHudAuthorActSpec _spec(L10n l10n, BeaconHudAuthorAction action) {
  final label = labelForBeaconHudAuthorAction(l10n, action);
  final effect = effectLineForBeaconHudAuthorAction(l10n, action);
  return BeaconHudAuthorActSpec(
    action: action,
    label: label,
    effectLine: effect,
    semanticsLabel: '$label. $effect',
    icon: iconForBeaconHudAuthorAction(action),
    filled: filledBeaconHudAuthorAction(action),
    effectPresentation: effectPresentationForBeaconHudAuthorAction(action),
  );
}

Future<void> _pump(WidgetTester tester, BeaconHudAuthorAction action) async {
  final l10n = L10nEn();
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await GetIt.I.reset();
  GetIt.I.registerSingleton<BeaconLobbyCase>(
    lobbyCaseFor(
      FakeLobbyPort(viewerId: 'Uauthor'),
      FakeRealtimeSyncPort(),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      // Built inside the test body: desktop platform, as on the web.
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(onPressed: () {}, child: const Text(_before)),
              // As on the Overview: Questions, then the action rail.
              const Material(
                child: BeaconLobbyEntryRow(beaconId: 'B1', isAuthor: true),
              ),
              BeaconHudAuthorActBlock(
                spec: _spec(l10n, action),
                onPressed: () {},
              ),
              BeaconHudActionButton(
                icon: Icons.send,
                label: l10n.labelForward,
                onPressed: () {},
              ),
              ElevatedButton(onPressed: () {}, child: const Text(_after)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(BeaconLobbyEntryRow.entryKey),
    findsOneWidget,
    reason: 'precondition: the author sees the Questions entry',
  );
}

void main() {
  final l10n = L10nEn();

  tearDown(() => GetIt.I.reset());

  for (final action in [
    BeaconHudAuthorAction.markEnoughHelp,
    BeaconHudAuthorAction.reviewOffers,
    BeaconHudAuthorAction.wrapUpForReview,
  ]) {
    testWidgets(
      '#415 Overview: Questions is one stop, the ${action.name} action and '
      'Forward each take the browser focus',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, action);

        final stops = await walkTabStops(
          tester,
          before: _before,
          after: _after,
        );
        // Questions, the author action, Forward, after.
        expect(stops, hasLength(4), reason: '$stops');
        expect(stops[0], contains(l10n.beaconLobbyTitle), reason: '$stops');
        expect(
          stops.where((s) => s.contains(l10n.beaconLobbyTitle)),
          hasLength(1),
          reason: 'Questions is one stop: $stops',
        );
        expect(
          stops[1],
          contains(labelForBeaconHudAuthorAction(l10n, action)),
          reason: '$stops',
        );
        expect(stops[1], isNot(contains(l10n.beaconLobbyTitle)));
        expect(stops[2], contains(l10n.labelForward), reason: '$stops');
        handle.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}
