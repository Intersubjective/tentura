import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

ForwardCandidate _candidate(
  String id, {
  double score = 1,
  bool reachable = true,
  CandidateInvolvement? involvement,
  List<String> topCapabilities = const [],
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: id,
    score: reachable ? score : 0,
    rScore: reachable ? 1 : 0,
  ),
  involvement: involvement ?? CandidateInvolvement.unseen,
  topCapabilities: topCapabilities,
);

ForwardCubit _cubit(
  List<ForwardCandidate> candidates, {
  Set<String> needs = const {},
}) {
  final cubit = ForwardCubit(
    beaconId: 'b1',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  cubit.emit(
    ForwardState(
      beaconId: 'b1',
      beacon: Beacon.empty.copyWith(id: 'b1', title: 'T', needs: needs),
      candidates: candidates,
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
  return cubit;
}

void main() {
  group('forward picker tag chips', () {
    test('tapping a tag selects only its eligible members', () {
      final cubit = _cubit([
        _candidate('a'),
        _candidate('b'),
        _candidate('hidden', reachable: false),
        _candidate(
          'done',
          involvement: CandidateInvolvement.forwardedByMe,
        ),
      ]);

      cubit.toggleTag('t1', ['a', 'b', 'hidden', 'done', 'unknown']);

      expect(cubit.state.selectedIds, {'a', 'b'});
      expect(cubit.state.addedByTag, {
        't1': {'a', 'b'},
      });
    });

    test('tapping the tag again removes the people it added', () {
      final cubit = _cubit([_candidate('a'), _candidate('b')]);

      cubit
        ..toggleTag('t1', ['a', 'b'])
        ..toggleTag('t1', ['a', 'b']);

      expect(cubit.state.selectedIds, isEmpty);
      expect(cubit.state.addedByTag, isEmpty);
    });

    test('second tap keeps people who were added individually', () {
      final cubit = _cubit([_candidate('a'), _candidate('b')]);

      cubit.toggleSelection('a');
      cubit
        ..toggleTag('t1', ['a', 'b'])
        ..toggleTag('t1', ['a', 'b']);

      expect(cubit.state.selectedIds, {'a'});
      expect(cubit.state.addedByTag, isEmpty);
    });

    test('a person added by two tags stays until both are removed', () {
      final cubit = _cubit([_candidate('a'), _candidate('b')]);

      cubit
        ..toggleTag('t1', ['a'])
        ..toggleTag('t2', ['a', 'b'])
        ..toggleTag('t1', ['a']);
      expect(cubit.state.selectedIds, {'a', 'b'});

      cubit.toggleTag('t2', ['a', 'b']);
      expect(cubit.state.selectedIds, isEmpty);
    });

    test('deselecting a person by hand drops it from the tag record', () {
      final cubit = _cubit([_candidate('a'), _candidate('b')]);

      cubit
        ..toggleTag('t1', ['a', 'b'])
        ..toggleSelection('a');

      expect(cubit.state.selectedIds, {'b'});
      expect(cubit.state.addedByTag['t1'], {'b'});
    });

    test('outside-the-tag hint lists at most three eligible non-members', () {
      final cubit = _cubit([
        _candidate('m1'),
        _candidate('o1', score: 5),
        _candidate('o2', score: 4),
        _candidate('o3', score: 3),
        _candidate('o4', score: 2),
        _candidate('o5', reachable: false),
      ]);

      final hint = cubit.state.outsideTagSuggestions(['m1']);

      expect(hint, hasLength(3));
      expect(hint.map((c) => c.id), isNot(contains('m1')));
      expect(hint.map((c) => c.id), isNot(contains('o5')));
    });

    test('hint ranks by the Request capability labels before score', () {
      final cubit = _cubit(
        [
          _candidate('m1'),
          _candidate('highScoreNoMatch', score: 9),
          _candidate('midScoreNoMatch', score: 5),
          _candidate('lowScoreMatch', topCapabilities: ['tools']),
          _candidate(
            'lowestScoreBothMatch',
            score: 0.5,
            topCapabilities: ['tools', 'ride'],
          ),
        ],
        needs: {'tools', 'ride'},
      );

      expect(
        cubit.state.outsideTagSuggestions(['m1']).map((c) => c.id),
        ['lowestScoreBothMatch', 'lowScoreMatch', 'highScoreNoMatch'],
      );
    });

    test('hint skips ineligible people and tag members', () {
      final cubit = _cubit([
        _candidate('m1', score: 9),
        _candidate('o1', score: 5, reachable: false),
        _candidate('o2', score: 4),
      ]);

      expect(
        cubit.state.outsideTagSuggestions(['m1']).map((c) => c.id),
        ['o2'],
      );
    });
  });

  group('forward picker tag copy', () {
    test('English strings exist for the individual-forward note and hint', () {
      final arb =
          jsonDecode(File('l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;

      expect(arb['peopleTagsForwardOutsideTag'], 'Outside the tag, could help');
      expect(arb['peopleTagsForwardNote'], isA<String>());
      expect((arb['peopleTagsForwardNote'] as String).trim(), isNotEmpty);
    });
  });
}
