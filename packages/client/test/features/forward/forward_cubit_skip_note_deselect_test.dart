import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

void main() {
  test('deselect clears personal note draft for reselect', () {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        candidates: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: 'Alex',
              score: 10,
              rScore: 1,
            ),
          ),
        ],
        selectedIds: {'u1'},
        perRecipientNotes: {'u1': 'hello'},
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    expect(
      cubit.toggleSelection('u1'),
      ForwardSelectionResult.deselected,
    );
    expect(cubit.state.perRecipientNotes, isEmpty);

    expect(
      cubit.toggleSelection('u1'),
      ForwardSelectionResult.selected,
    );
    expect(cubit.state.perRecipientNotes, isEmpty);
  });

  test('clearLineageSuggestions prunes notes for deselected lineage ids', () {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        selectedIds: {'u-main', 'u-lineage'},
        perRecipientNotes: {'u-main': 'a', 'u-lineage': 'b'},
        lineageSuggestions: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u-lineage',
              displayName: 'Lineage',
              score: 5,
              rScore: 1,
            ),
          ),
        ],
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    cubit.clearLineageSuggestions();

    expect(cubit.state.perRecipientNotes, {'u-main': 'a'});
  });
}
