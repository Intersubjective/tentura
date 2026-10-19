// #487 — the flag (NOW) row on a Requests card. A new Request has no next
// step, and the card printed the placeholder ("No next step yet", earlier
// "Nothing noted yet") under a flag icon that nothing explained. The row is
// hidden while there is nothing to show, and when it shows, the flag says
// what it is ("Next step", the name the Request page already uses).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

final _beacon = Beacon.empty.copyWith(
  id: 'b-couch',
  title: 'Need a hand moving a couch',
  status: BeaconStatus.open,
  author: const Profile(id: 'viewer', displayName: 'Vadim'),
);

MyWorkCardViewModel _vm({
  String currentLine = '',
  String blocker = '',
}) => MyWorkCardViewModel(
  beaconId: _beacon.id,
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: _beacon,
  roomCurrentLine: currentLine,
  roomOpenBlockerTitle: blocker,
);

Future<L10n> _pump(
  WidgetTester tester,
  MyWorkCardViewModel vm, {
  Locale locale = const Locale('en'),
}) async {
  late L10n l10n;
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(480, 800)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: Builder(
                builder: (context) {
                  l10n = L10n.of(context)!;
                  return MyWorkCardMetadataRow(
                    beacon: vm.beacon,
                    viewModel: vm,
                    currentUserId: 'viewer',
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

/// The flag is named either by a tooltip on it or by a visible label.
bool _flagIsNamed(String name) =>
    find.byTooltip(name).evaluate().isNotEmpty ||
    find.textContaining(name).evaluate().isNotEmpty;

void main() {
  testWidgets('an open Request with no next step shows no flag row', (
    tester,
  ) async {
    final l10n = await _pump(tester, _vm());

    expect(find.byIcon(BeaconHudRowIcons.now), findsNothing);
    expect(find.text(l10n.beaconHudNoCurrentLine), findsNothing);
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('a whitespace-only next step counts as none', (tester) async {
    final l10n = await _pump(tester, _vm(currentLine: '   '));

    expect(find.byIcon(BeaconHudRowIcons.now), findsNothing);
    expect(find.text(l10n.beaconHudNoCurrentLine), findsNothing);
  });

  testWidgets('ru: no placeholder row either', (tester) async {
    final l10n = await _pump(tester, _vm(), locale: const Locale('ru'));

    expect(find.byIcon(BeaconHudRowIcons.now), findsNothing);
    expect(find.text(l10n.beaconHudNoCurrentLine), findsNothing);
  });

  testWidgets('guard: a next step still shows its row and text', (
    tester,
  ) async {
    await _pump(tester, _vm(currentLine: 'Pick up the van at noon'));

    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.textContaining('Pick up the van at noon'), findsOneWidget);
  });

  testWidgets('guard: an open blocker keeps the row without a next step', (
    tester,
  ) async {
    final l10n = await _pump(tester, _vm(blocker: 'Van keys'));

    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.text(l10n.beaconHudNowBlocked('Van keys')), findsOneWidget);
  });

  testWidgets('the flag row is named "Next step"', (tester) async {
    final l10n = await _pump(
      tester,
      _vm(currentLine: 'Pick up the van at noon'),
    );

    expect(l10n.beaconSituationCurrentLineLabel, 'Next step');
    expect(_flagIsNamed(l10n.beaconSituationCurrentLineLabel), isTrue);
  });

  testWidgets('ru: the flag row is named', (tester) async {
    final l10n = await _pump(
      tester,
      _vm(currentLine: 'Забрать фургон в полдень'),
      locale: const Locale('ru'),
    );

    expect(l10n.beaconSituationCurrentLineLabel, 'Следующий шаг');
    expect(_flagIsNamed(l10n.beaconSituationCurrentLineLabel), isTrue);
  });
}
