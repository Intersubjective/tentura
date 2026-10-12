// The «Закрыть пост…» choice of a Post→Request bud must never close the Post
// on people the budder did not invite: its default follows the whole effective
// membership, stays off while that membership is unknown, and the bud cannot
// be submitted until the invite candidates have loaded.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'post_bud_fakes.dart';

Future<BeaconCreateCubit> _openLoaded(BudHarness h) async {
  final cubit = h.cubit(effects: FakeUiEffectPort());
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.postBud?.candidatesLoaded ?? false);
  return cubit;
}

void main() {
  group('close-Post default follows the whole effective membership', () {
    test(
      'off when a member who is not invitable would be left outside the bud',
      () async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('a', pretick: true),
          budCandidate('b', pretick: true),
          budCandidate('paused', outcome: PostBudInviteOutcome.notEligible),
        ];
        final cubit = await _openLoaded(h);

        final bud = cubit.state.postBud!;
        expect(bud.memberCount, 4);
        expect(bud.selectedIds, {'a', 'b'});
        expect(bud.closePost, isFalse);

        await cubit.submitBud(context: '');
        expect(h.port.calls.single.closePost, isFalse);
      },
    );

    test(
      'off when every invitable member is ticked but a blocked one remains',
      () async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('a', pretick: true),
          budCandidate('b', pretick: true),
          budCandidate('blocked', outcome: PostBudInviteOutcome.blocked),
        ];
        final cubit = await _openLoaded(h);
        expect(cubit.state.postBud!.closePost, isFalse);
      },
    );

    test('on when every member of the Post is ticked', () async {
      final h = BudHarness();
      h.port.candidates = [
        budCandidate('a', pretick: true),
        budCandidate('b', pretick: true),
        budCandidate('c', pretick: true),
      ];
      final cubit = await _openLoaded(h);
      expect(cubit.state.postBud!.closePost, isTrue);

      cubit.setBudInviteeSelected('c', selected: false);
      expect(cubit.state.postBud!.closePost, isFalse);
    });
  });

  group('bud before the invite candidates are known', () {
    test(
      'close-Post stays off and submit sends nothing while loading',
      () async {
        final h = BudHarness();
        h.port.candidatesGate = Completer<void>();
        h.port.candidates = [
          budCandidate('a', pretick: true),
          budCandidate('b', pretick: true),
          budCandidate('c'),
        ];
        final cubit = h.cubit(effects: FakeUiEffectPort());
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((s) => s.postBud != null);
        await pumpEventQueue();

        final bud = cubit.state.postBud!;
        expect(bud.candidatesLoaded, isFalse);
        expect(bud.closePost, isFalse);
        expect(await cubit.submitBud(context: ''), isNull);
        expect(h.port.calls, isEmpty);

        h.port.candidatesGate!.complete();
        await cubit.stream.firstWhere(
          (s) => s.postBud?.candidatesLoaded ?? false,
        );
        expect(await cubit.submitBud(context: ''), isNotNull);
        expect(h.port.calls, hasLength(1));
      },
    );

    test(
      'a failed candidate load keeps submit blocked until a retry succeeds',
      () async {
        final h = BudHarness();
        final effects = FakeUiEffectPort();
        h.port
          ..candidatesError = Exception('offline')
          ..candidates = [
            budCandidate('a', pretick: true),
            budCandidate('b'),
            budCandidate('c'),
          ];
        final cubit = h.cubit(effects: effects);
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((s) => s.postBud != null);
        await pumpEventQueue();
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);

        expect(cubit.state.postBud!.candidatesLoaded, isFalse);
        expect(cubit.state.postBud!.closePost, isFalse);
        expect(await cubit.submitBud(context: ''), isNull);
        expect(h.port.calls, isEmpty);

        h.port.candidatesError = null;
        await cubit.loadBudInviteCandidates();
        expect(cubit.state.postBud!.candidatesLoaded, isTrue);
        expect(await cubit.submitBud(context: ''), isNotNull);
        expect(h.port.calls.single.closePost, isFalse);
      },
    );
  });
}
