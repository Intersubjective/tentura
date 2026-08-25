import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

ForwardCandidate _candidate(String id, {String name = 'Alex'}) =>
    ForwardCandidate(
      profile: Profile(
        id: id,
        displayName: name,
        score: 10,
        rScore: 1,
      ),
    );

void main() {
  test('deselect after skip clears skippedPersonalNoteIds for reselect', () {
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    cubit.emit(
      ForwardState(
        beaconId: 'b1',
        beacon: Beacon.empty.copyWith(id: 'b1', title: 'T'),
        candidates: [_candidate('u1')],
        selectedIds: {'u1'},
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    cubit.skipPersonalNote('u1');
    expect(cubit.state.skippedPersonalNoteIds, {'u1'});

    expect(
      cubit.toggleSelection('u1'),
      ForwardSelectionResult.deselected,
    );
    expect(cubit.state.selectedIds, isEmpty);
    expect(cubit.state.skippedPersonalNoteIds, isEmpty);

    expect(
      cubit.toggleSelection('u1'),
      ForwardSelectionResult.selected,
    );
    expect(cubit.state.selectedIds, {'u1'});
    expect(cubit.state.skippedPersonalNoteIds, isEmpty);
  });

  test('clearLineageSuggestions prunes skip notes and reasons', () {
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    cubit.emit(
      ForwardState(
        beaconId: 'b1',
        beacon: Beacon.empty.copyWith(id: 'b1', title: 'T'),
        candidates: [_candidate('u-main', name: 'Main')],
        lineageSuggestions: [_candidate('u-lineage', name: 'Lineage')],
        selectedIds: {'u-main', 'u-lineage'},
        perRecipientNotes: {
          'u-main': 'keep',
          'u-lineage': 'drop',
        },
        recipientReasons: {
          'u-main': const ['r1'],
          'u-lineage': const ['r2'],
        },
        skippedPersonalNoteIds: {'u-main', 'u-lineage'},
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    cubit.clearLineageSuggestions();

    expect(cubit.state.selectedIds, {'u-main'});
    expect(cubit.state.skippedPersonalNoteIds, {'u-main'});
    expect(cubit.state.perRecipientNotes, {'u-main': 'keep'});
    expect(cubit.state.recipientReasons, {
      'u-main': ['r1'],
    });
    expect(cubit.state.note, isEmpty);
  });
}
