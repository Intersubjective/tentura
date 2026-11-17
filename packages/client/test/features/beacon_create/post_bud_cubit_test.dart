// Budding a Request from a Post message (plan D1): the Request form detects a
// Post parent, prefills from the source message, takes the invitees from the
// invite step's Forward picker cubit (which ticks the members the server
// pre-ticks), and submits one `beaconBudFromPost` per screen session no matter
// how often the button is tapped.
//
// The «Закрыть пост…» default and the many-invites warning are driven through
// the screen: post_bud_close_post_default_test.dart, post_bud_screen_test.dart
// and post_bud_invite_picker_test.dart.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'post_bud_fakes.dart';

Future<BeaconCreateCubit> _open(
  BudHarness h, {
  FakeUiEffectPort? effects,
  bool enabled = true,
}) async {
  final cubit = h.cubit(
    effects: effects ?? FakeUiEffectPort(),
    enabled: enabled,
  );
  addTearDown(cubit.close);
  if (enabled) {
    await cubit.stream.firstWhere((s) => s.postBud != null);
  } else {
    await cubit.stream.firstWhere((s) => s.clientCommandId != null);
  }
  return cubit;
}

/// The invite step's loaded [ForwardCubit] over [h]'s fake bud port.
Future<ForwardCubit> _inviteCubit(BudHarness h) async {
  final forward = await BudForward.start(h);
  addTearDown(forward.dispose);
  final cubit = await forward.inviteCubit();
  addTearDown(cubit.close);
  return cubit;
}

/// Submits the bud with the invitees ticked in [forward], the invite step's
/// picker cubit.
Future<PostBudResult?> _submit(
  BeaconCreateCubit cubit,
  ForwardCubit forward,
) => cubit.submitBud(context: '', forwardCubit: forward);

void main() {
  tearDown(() async => GetIt.I.reset());

  group('MessagePrefillCase.fromText', () {
    test('first line is the title, the rest the description', () {
      final p = MessagePrefillCase.fromText('  Need a ladder\n\nSaturday.\n');
      expect(p.title, 'Need a ladder');
      expect(p.description, 'Saturday.');
    });

    test('a one-line message leaves the description empty', () {
      final p = MessagePrefillCase.fromText('Just this');
      expect(p.title, 'Just this');
      expect(p.description, isEmpty);
    });
  });

  group('bud mode', () {
    test(
      'a Post parent prefills from the source message, discoverable off',
      () async {
        final h = BudHarness(
          parent: budPost(forwardPolicy: BeaconForwardPolicyValue.closed),
        );
        final cubit = await _open(h);

        final s = cubit.state;
        expect(s.isPostBud, isTrue);
        expect(s.title, 'Need a ladder');
        expect(s.description, 'For Saturday at noon.');
        expect(s.isDiscoverable, isFalse);
        expect(s.images, isEmpty);
        expect(s.postBud!.postId, kBudPostId);
        expect(s.postBud!.sourceMessageId, kBudSourceMessageId);
        expect(s.postBud!.postForwardingClosed, isTrue);
        expect(s.postBud!.clientCommandId, isNotEmpty);
        // Nothing is saved as a child draft before submit.
        expect(h.hierarchy.createCalls, isEmpty);
      },
    );

    test('a Request parent stays an ordinary child composer', () async {
      final h = BudHarness(parent: Beacon.empty.copyWith(id: kBudPostId));
      final cubit = h.cubit(effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.clientCommandId != null);
      expect(cubit.state.isPostBud, isFalse);
    });

    test('gate off: a Post parent is not detected', () async {
      final h = BudHarness();
      final cubit = await _open(h, enabled: false);
      expect(cubit.state.isPostBud, isFalse);
    });

    test('the invite picker ticks only invitable pre-ticked members and '
        'lists the invitable ones in server order (writers first)', () async {
      final h = BudHarness();
      h.port.candidates = [
        budCandidate('writer', hasWritten: true, pretick: true),
        budCandidate(
          'blocked',
          hasWritten: true,
          pretick: true,
          outcome: PostBudInviteOutcome.blocked,
        ),
        budCandidate('silent', pretick: true),
        budCandidate('plain'),
      ];
      await _open(h);
      final forward = await _inviteCubit(h);

      expect(forward.state.selectedIds, {'silent', 'writer'});
      expect(forward.state.candidates.map((c) => c.id), [
        'writer',
        'silent',
        'plain',
      ]);
    });

    test(
      'submit sends the form, the ticked invitees with notes and closePost',
      () async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('a', hasWritten: true, pretick: true),
          budCandidate('b'),
          budCandidate('c', pretick: true),
        ];
        final cubit = await _open(h);
        final forward = await _inviteCubit(h);
        expect(forward.state.selectedIds, {'a', 'c'});
        forward
          ..toggleSelection('c')
          ..toggleSelection('b')
          ..setRecipientNote('b', '  you know the place  ');
        cubit
          ..setNeeds({'transport'})
          ..setDiscoverable(true);

        final result = await _submit(cubit, forward);

        expect(result?.childBeaconId, 'child-1');
        expect(h.port.calls, hasLength(1));
        final call = h.port.calls.single;
        expect(call.clientCommandId, cubit.state.postBud!.clientCommandId);
        expect(call.title, 'Need a ladder');
        expect(call.description, 'For Saturday at noon.');
        expect(call.isDiscoverable, isTrue);
        expect(call.needs, 'transport');
        expect(call.invitees, const [
          PostBudInvitee(userId: 'a'),
          PostBudInvitee(userId: 'b', note: 'you know the place'),
        ]);
        expect(call.closePost, isFalse);
        expect(cubit.state.isLive, isTrue);
        expect(cubit.state.draftId, 'child-1');
      },
    );

    test(
      'repeat taps send one bud; a retry reuses the clientCommandId',
      () async {
        final h = BudHarness();
        final effects = FakeUiEffectPort();
        final cubit = await _open(h, effects: effects);
        final forward = await _inviteCubit(h);
        h.port.gate = Completer<void>();

        final first = _submit(cubit, forward);
        final second = _submit(cubit, forward);
        h.port.gate!.complete();
        expect(await second, isNull);
        expect(await first, isNotNull);
        expect(h.port.calls, hasLength(1));

        h.port
          ..gate = null
          ..budError = Exception('offline');
        expect(await _submit(cubit, forward), isNull);
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
        h.port.budError = null;
        expect(await _submit(cubit, forward), isNotNull);

        expect(h.port.calls, hasLength(3));
        expect(
          h.port.calls.map((c) => c.clientCommandId).toSet(),
          hasLength(1),
        );
      },
    );

    test('notInvitedUserIds lists the invitees the server skipped', () {
      const result = PostBudResult(
        outcome: PostBudOutcome.created,
        childBeaconId: 'c',
        invitees: [
          PostBudInviteeResult(
            userId: 'a',
            outcome: PostBudInviteOutcome.invited,
          ),
          PostBudInviteeResult(
            userId: 'b',
            outcome: PostBudInviteOutcome.recipientPaused,
          ),
        ],
      );
      expect(result.notInvitedUserIds, ['b']);
    });
  });
}
