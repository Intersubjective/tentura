// #475: every post-publish Request status sheet led with a greyed-out
// "Draft" row ("Save as draft until you publish") that can never apply once
// the Request is published. Drafts live in the editor; the Draft row belongs
// only to the sheet of a Request that is still a draft.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

final _t = DateTime.utc(2026, 6, 20, 12);

BeaconStatusMenuInput _input(BeaconStatus status) => BeaconStatusMenuInput(
  beacon: Beacon.empty.copyWith(
    id: 'b1',
    title: 'Test',
    status: status,
    createdAt: _t,
    updatedAt: _t,
  ),
  closureReadiness: BeaconClosureReadiness.readyToClose,
  hasCommitters: true,
  canManageLifecycle: true,
  canSetCoordination: true,
  closure: const ClosureMenuSnapshot(extensionsUsed: 0),
);

List<BeaconStatusMenuRowId> _ids(BeaconStatus status) => [
  for (final row in buildBeaconStatusMenuRows(_input(status))) row.id,
];

/// The sheet of a published Request: every row except Draft, same order.
const _postPublishIds = [
  BeaconStatusMenuRowId.open,
  BeaconStatusMenuRowId.moreHelp,
  BeaconStatusMenuRowId.enoughHelp,
  BeaconStatusMenuRowId.wrappingUp,
  BeaconStatusMenuRowId.closed,
  BeaconStatusMenuRowId.cancelled,
];

void main() {
  group('#475 post-publish status sheet has no Draft row', () {
    for (final status in [
      BeaconStatus.open,
      BeaconStatus.needsMoreHelp,
      BeaconStatus.enoughHelp,
      BeaconStatus.reviewOpen,
    ]) {
      test('${status.name}: no Draft row, the other six in order', () {
        final ids = _ids(status);
        expect(ids, isNot(contains(BeaconStatusMenuRowId.draft)));
        expect(ids, _postPublishIds);
      });
    }

    for (final status in [BeaconStatus.closed, BeaconStatus.cancelled]) {
      test('${status.name} (terminal): no Draft row either', () {
        final ids = _ids(status);
        expect(ids, isNot(contains(BeaconStatusMenuRowId.draft)));
        expect(ids, _postPublishIds);
      });
    }
  });

  group('#475 guard: a Request that is still a draft keeps its Draft row', () {
    test('draft sheet still leads with the selected Draft row', () {
      final rows = buildBeaconStatusMenuRows(_input(BeaconStatus.draft));
      expect(
        [for (final r in rows) r.id],
        [BeaconStatusMenuRowId.draft, ..._postPublishIds],
      );
      expect(rows.first.isSelected, isTrue);
      final open = rows.firstWhere((r) => r.id == BeaconStatusMenuRowId.open);
      expect(open.action, BeaconStatusMenuAction.publish);
      expect(open.isEnabled, isTrue);
    });
  });

  testWidgets('#475 the open Request status sheet shows no Draft row', (
    tester,
  ) async {
    const author = Profile(id: 'Uauthor', displayName: 'Author');
    const beaconId = 'Bstatus475';
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = (await tester.runAsync(() async {
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: author,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: TrackingBeaconRepository()
            ..fetchByIdHandler = (_) async => Beacon(
              id: beaconId,
              title: 'Status beacon',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              author: author,
            ),
        ),
        effects: FakeUiEffectPort(),
      );
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
      return cubit;
    }))!;
    addTearDown(cubit.close);
    expect(cubit.state.beacon.status, BeaconStatus.open);
    final l10n = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 1200)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () =>
                      showBeaconViewUpdateStatusSheet(ctx, cubit.state, cubit),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconStatusSheetTitle), findsOneWidget);

    Finder rowKey(BeaconStatusMenuRowId id) =>
        find.byKey(TestIds.key(TestIds.beaconStatusRow(id.name)));

    expect(rowKey(BeaconStatusMenuRowId.draft), findsNothing);
    expect(find.text(l10n.beaconStatusRowDraft), findsNothing);
    expect(find.text(l10n.beaconStatusRowOutcomeDraft), findsNothing);

    // Vacuity guard: the sheet itself still lists the published rows.
    for (final id in _postPublishIds) {
      expect(rowKey(id), findsOneWidget, reason: id.name);
    }
  });
}
