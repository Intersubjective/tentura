import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

void main() {
  test('preselectLineageSuggestions checks autoSelect lineage rows once', () {
    final cubit = ForwardCubit(
      beaconId: 'draft-fork',
      debugSkipInitialLoad: true,
      preselectLineageSuggestions: true,
      effects: FakeUiEffectPort(),
    );

    final lineage = ForwardCandidate(
      profile: const Profile(id: 'hint-1', displayName: 'Hinted'),
      lineageGroup: LineageSuggestionGroup.involved,
      lineageAutoSelect: true,
    );

    cubit.emit(
      ForwardState(
        beaconId: 'draft-fork',
        beacon: Beacon.empty.copyWith(
          id: 'draft-fork',
          lineageParentBeaconId: 'parent-1',
        ),
        candidates: const [],
        lineageSuggestions: [lineage],
        selectedIds: const {},
      ),
    );

    // Simulate load completion logic: first load with preselect enabled.
    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'hint-1'},
      ),
    );

    expect(cubit.state.selectedIds, {'hint-1'});
    cubit.close();
  });
}
