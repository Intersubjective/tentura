// #415 (QA residual on dev 7.41.26): in the request room some controls still
// took several Tab presses on the web — «More actions» two, every message
// group two, and the NOW row's «Edit next step» pencil five before Forward.
//
// On the web the browser's focused element is the element of the semantics
// node that says it has focus. Several controls name themselves with an
// outer `Semantics(label: ..., excludeSemantics / ExcludeSemantics)` around
// their InkWell or IconButton, which also hides that control's focus state;
// the message bubble's own focus node had no semantics at all. Tab still
// moved Flutter's focus onto them, but no node said so, so the browser kept
// focus on the previous control: «pencil» for the four HUD counters after
// it, «More actions» for the first message, and so on.
//
// Spec: every Tab stop puts the focus on a semantics node of its own, so
// each press moves the browser's focus once, to the next control.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';

import '../../support/a11y_focus.dart';

const _before = 'Control before';
const _after = 'Control after';
const _me = Profile(id: 'ME', displayName: 'Nina');
const _author = Profile(id: 'UA', displayName: 'Tab QA');
const _anna = Profile(id: 'U2', displayName: 'Anna');

Future<void> _pump(WidgetTester tester, Widget subject) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
              subject,
              ElevatedButton(onPressed: () {}, child: const Text(_after)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FocusNode _buttonNode(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label)));

String _describeFocus() {
  final focus = FocusManager.instance.primaryFocus;
  return '${focus?.debugLabel ?? focus?.runtimeType} '
      '(${focus?.context?.widget.runtimeType})';
}

/// Tabs from the «before» button to the «after» one. At every stop, expects
/// a focused semantics node, and a different one than at the previous stop.
/// Returns what each stop's focused node says, in Tab order.
Future<List<String>> _walk(WidgetTester tester) async {
  final after = _buttonNode(tester, _after);
  _buttonNode(tester, _before).requestFocus();
  // requestFocus applies in a microtask after this pump's (absent) frame;
  // the second pump rebuilds Focus's semantics with the new focus.
  await tester.pump();
  await tester.pump();
  var previous = focusedSemanticsNodes().map((n) => n.id).toSet();
  expect(previous, isNotEmpty, reason: 'precondition: «before» is focused');
  final seen = <String>[];
  for (var i = 0; i < 30; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final nodes = focusedSemanticsNodes();
    final said = nodes.map(describeSemanticsNode).join(' + ');
    final ids = nodes.map((n) => n.id).toSet();
    expect(
      ids,
      isNotEmpty,
      reason:
          'Tab ${i + 1} focused ${_describeFocus()}, but no semantics node '
          'says it has focus: on the web the browser keeps focus on the '
          'previous control (${seen.isEmpty ? _before : seen.last}). '
          'Stops so far: $seen',
    );
    expect(
      ids,
      isNot(equals(previous)),
      reason:
          'Tab ${i + 1} (${_describeFocus()}) left the browser focus on the '
          'same node as the previous press ($said). Stops so far: $seen',
    );
    seen.add(said);
    previous = ids;
    if (identical(FocusManager.instance.primaryFocus, after)) return seen;
  }
  fail('Tab never reached «after»: $seen');
}

void main() {
  testWidgets(
    '#415 HUD rows, pencil, avatar and (i): each Tab moves the browser focus',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BeaconHudMetadataTable(
                buildEntries: (_) => [
                  BeaconHudMetadataEntry(
                    icon: Icons.flag_outlined,
                    semanticsLabel: 'Next step',
                    body: const Text('Bring the ladder'),
                    onTap: () {},
                    trailing: hudNowRowEditButton(
                      context: context,
                      onEdit: () {},
                      editSemanticLabel: 'Edit next step',
                    ),
                  ),
                  BeaconHudMetadataEntry(
                    icon: Icons.checklist,
                    semanticsLabel: 'Plan',
                    body: const Text('1 of 3 steps'),
                    onTap: () {},
                  ),
                ],
              ),
              HudLabeledMultiline(
                leadingIcon: Icons.info_outline,
                semanticsLabel: 'Details',
                text: 'Saturday morning, the garage',
                mutedColor: Colors.grey,
                onShowDetail: () {},
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TenturaAvatar(profile: _anna, onTap: () {}),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: TenturaInfoHintButton(fullText: 'How offers work'),
              ),
            ],
          ),
        ),
      );

      final stops = await _walk(tester);
      // Next step row, pencil, Plan row, Details row, avatar, (i), after.
      expect(stops, hasLength(7), reason: '$stops');
      expect(stops[1], contains('Edit next step'), reason: '$stops');
      expect(stops[2], contains('Plan'), reason: '$stops');
      expect(stops[4], contains('Anna'), reason: '$stops');
      expect(stops[5], contains('How offers work'), reason: '$stops');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    '#415 Now pane: one Tab takes the browser focus off the NOW pencil',
    (tester) async {
      final handle = tester.ensureSemantics();
      final state = BeaconViewState(
        beacon: Beacon.empty.copyWith(
          id: 'B1',
          updatedAt: DateTime.utc(2026),
          author: _author,
          status: BeaconStatus.open,
        ),
        myProfile: _me,
        beaconRoomCue: BeaconRoomState(
          beaconId: 'B1',
          updatedAt: DateTime.utc(2026, 10, 14, 9),
          currentLine: 'Van at 9:45',
          updatedBy: 'UA',
        ),
      );
      await _pump(
        tester,
        BeaconHudPinnedBlock(
          state: state,
          now: DateTime.utc(2026, 10, 14, 9, 5),
          onEditStep: () {},
          onOpenTeam: () {},
          onOpenSubrequests: () {},
          subrequestCount: 2,
        ),
      );
      expect(
        find.byTooltip('Edit next step'),
        findsOneWidget,
        reason: 'precondition: the NOW row has its pencil',
      );

      final stops = await _walk(tester);
      final pencil = stops.indexWhere((s) => s.contains('Edit next step'));
      expect(pencil, isNonNegative, reason: 'the pencil is a stop: $stops');
      // The HUD counters after the pencil are stops of their own, each
      // focusing its own node (the walk checks every press).
      expect(
        stops.sublist(pencil + 1, stops.length - 1),
        hasLength(greaterThanOrEqualTo(2)),
        reason: 'the team and sub-request counters follow the pencil: $stops',
      );
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
