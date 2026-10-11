// Budding a Request from a Post message (plan D1): the Request form detects a
// Post parent, prefills from the source message, ticks the members the server
// pre-ticks, defaults «Закрыть пост…», and submits one `beaconBudFromPost` per
// screen session no matter how often the button is tapped.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
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
    await cubit.stream.firstWhere(
      (s) => s.postBud?.candidatesLoaded ?? false,
    );
  } else {
    await cubit.stream.firstWhere((s) => s.clientCommandId != null);
  }
  return cubit;
}

void main() {
  group('MessagePrefillCase.fromText', () {
    test('first line is the title, the rest the description', () {
      final p = MessagePrefillCase.fromText('  Need a ladder\n\nSaturday.\n');
      expect(p.title, 'Need a ladder');
      expect(p.description, 'Saturday.');
      expect(p.coverSuggestion, isNull);
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

    test(
      'pretick ticks only invitable pre-ticked members; writers first',
      () async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('silent', pretick: true),
          budCandidate('writer', hasWritten: true, pretick: true),
          budCandidate(
            'blocked',
            hasWritten: true,
            pretick: true,
            outcome: PostBudInviteOutcome.blocked,
          ),
          budCandidate('plain'),
        ];
        final cubit = await _open(h);

        final bud = cubit.state.postBud!;
        expect(bud.selectedIds, {'silent', 'writer'});
        expect(
          bud.invitable.map((c) => c.userId),
          ['writer', 'silent', 'plain'],
        );
        expect(bud.memberCount, 5);
      },
    );

    group('«Закрыть пост…» default', () {
      test('on when E(P) has at most two members', () async {
        final h = BudHarness();
        h.port.candidates = [budCandidate('only')];
        final cubit = await _open(h);
        expect(cubit.state.postBud!.closePost, isTrue);
      });

      test('on iff every eligible member is ticked', () async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('a', pretick: true),
          budCandidate('b', pretick: true),
          budCandidate('c', outcome: PostBudInviteOutcome.notEligible),
        ];
        final cubit = await _open(h);
        expect(cubit.state.postBud!.closePost, isTrue);

        cubit.setBudInviteeSelected('b', selected: false);
        expect(cubit.state.postBud!.closePost, isFalse);
      });

      test("the budder's own choice wins over the default", () async {
        final h = BudHarness();
        h.port.candidates = [budCandidate('only')];
        final cubit = await _open(h);
        cubit.setBudClosePost(false);
        expect(cubit.state.postBud!.closePost, isFalse);
      });
    });

    test('more than five ticked shows the warning', () async {
      final h = BudHarness();
      h.port.candidates = [
        for (var i = 0; i < 6; i++) budCandidate('u$i', pretick: i < 5),
      ];
      final cubit = await _open(h);
      expect(cubit.state.postBud!.showsManyInvitesWarning, isFalse);
      cubit.setBudInviteeSelected('u5', selected: true);
      expect(cubit.state.postBud!.showsManyInvitesWarning, isTrue);
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
        cubit
          ..setBudInviteeSelected('c', selected: false)
          ..setBudInviteeSelected('b', selected: true)
          ..setBudInviteeNote('b', '  you know the place  ')
          ..setNeeds({'transport'})
          ..setDiscoverable(true);

        final result = await cubit.submitBud(context: '');

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
        h.port.gate = Completer<void>();

        final first = cubit.submitBud(context: '');
        final second = cubit.submitBud(context: '');
        h.port.gate!.complete();
        expect(await second, isNull);
        expect(await first, isNotNull);
        expect(h.port.calls, hasLength(1));

        h.port
          ..gate = null
          ..budError = Exception('offline');
        expect(await cubit.submitBud(context: ''), isNull);
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
        h.port.budError = null;
        expect(await cubit.submitBud(context: ''), isNotNull);

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
