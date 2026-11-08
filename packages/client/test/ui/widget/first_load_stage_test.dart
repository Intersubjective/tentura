import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_stage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('first load stage helpers', () {
    test('my work advances desk → closure → attention', () {
      const en = Locale('en');
      final l10n = lookupL10n(en);
      var state = const MyWorkState();
      var progress = myWorkFirstLoadProgress(state, l10n)!;
      expect(progress.step, 1);
      expect(progress.stageLabel, l10n.firstLoadStageMyWorkDesk);

      state = state.copyWith(deskInitLoaded: true);
      progress = myWorkFirstLoadProgress(state, l10n)!;
      expect(progress.step, 2);
      expect(progress.stageLabel, l10n.firstLoadStageMyWorkClosure);

      state = state.copyWith(nonArchivedProjectionLoaded: true);
      progress = myWorkFirstLoadProgress(state, l10n)!;
      expect(progress.step, 3);
      expect(progress.stageLabel, l10n.firstLoadStageMyWorkAttention);

      state = state.copyWith(firstLoadDone: true);
      expect(myWorkFirstLoadProgress(state, l10n), isNull);
    });

    test('request tracks beacon, thread, then hierarchy', () {
      const en = Locale('en');
      final l10n = lookupL10n(en);
      var beacon = BeaconViewState(
        beacon: Beacon.empty.copyWith(id: 'b', title: 'Harness'),
        myProfile: const Profile(id: 'u', displayName: 'Viewer'),
      );
      var progress = requestFirstLoadProgress(
        l10n: l10n,
        beacon: beacon,
        roomExpected: true,
        roomFirstLoadDone: false,
        hierarchyBlocks: false,
      )!;
      expect(progress.step, 1);
      expect(progress.stageLabel, l10n.firstLoadStageRequestBeacon);

      beacon = beacon.copyWith(firstLoadDone: true);
      progress = requestFirstLoadProgress(
        l10n: l10n,
        beacon: beacon,
        roomExpected: true,
        roomFirstLoadDone: false,
        hierarchyBlocks: false,
      )!;
      expect(progress.step, 2);
      expect(progress.stageLabel, l10n.firstLoadStageRequestThread);

      progress = requestFirstLoadProgress(
        l10n: l10n,
        beacon: beacon,
        roomExpected: true,
        roomFirstLoadDone: true,
        hierarchyBlocks: true,
      )!;
      expect(progress.step, 3);
      expect(progress.stageLabel, l10n.firstLoadStageRequestHierarchy);
    });
  });
}
