import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/like/domain/exception.dart';

import '../../support/graph_trust_write_fixture.dart';

// The person context shows a trust change at once, writes it lazily through
// the account-owned write case and never re-reads a profile for it. Pinned

const _alice = Profile(id: 'Ualice', displayName: 'Alice');
const _bob = Profile(id: 'Ubob', displayName: 'Bob');

Future<void> _settle() => pumpEventQueue(times: 5);

final _transport = TimeoutException('no answer');

void main() {
  group('GraphPersonContextCubit speculative trust', () {
    late GraphTrustWriteFixture fixture;
    late GraphPersonContextCubit cubit;
    late List<Profile> patched;

    setUp(() async {
      fixture = GraphTrustWriteFixture();
      fixture.profiles.byId
        ..['Ualice'] = _alice
        ..['Ubob'] = _bob;
      patched = [];
      cubit = fixture.createCubit(
        onProfilePatched: patched.add,
      );
      fixture.account.add('Ume');
      cubit.selectProfile(_alice, intentional: true);
      await _settle();
    });

    tearDown(() => fixture.dispose());

    test('trusting shows the new state before the server answers', () async {
      unawaited(cubit.trustSelected());
      await _settle();

      expect(fixture.likes.calls, hasLength(1));
      expect(cubit.state.selectedProfile!.myVote, 1);
      expect(patched.last.myVote, 1);
      expect(cubit.state.trustError, isNull);
    });

    test('withdrawing trust shows the new state at once', () async {
      fixture.profiles.byId['Ualice'] = _alice.copyWith(myVote: 1);
      cubit.selectProfile(_alice.copyWith(myVote: 1), intentional: true);
      await _settle();

      unawaited(cubit.untrustSelected());
      await _settle();

      expect(fixture.likes.amounts, [0]);
      expect(cubit.state.selectedProfile!.myVote, 0);
      expect(patched.last.myVote, 0);
    });

    test('the state has no loading flag for a trust change', () async {
      unawaited(cubit.trustSelected());
      await _settle();

      expect(
        () => (cubit.state as dynamic).trustLoading,
        throwsNoSuchMethodError,
      );
    });

    test('a trust change triggers no profile re-read', () async {
      final readsBefore = fixture.profiles.fetchCalls;

      unawaited(cubit.trustSelected());
      await _settle();
      fixture.likes.ack(0);
      await _settle();

      expect(fixture.likes.amounts, [1]);
      expect(fixture.profiles.fetchCalls, readsBefore);
      expect(cubit.state.selectedProfile!.myVote, 1);
    });

    test('toggling back before the answer shows the last value', () async {
      unawaited(cubit.trustSelected());
      await _settle();
      unawaited(cubit.untrustSelected());
      await _settle();

      expect(cubit.state.selectedProfile!.myVote, 0);
      expect(fixture.likes.amounts, [1]);

      fixture.likes.ack(0);
      await _settle();

      expect(fixture.likes.amounts, [1, 0]);
      expect(cubit.state.selectedProfile!.myVote, 0);
    });

    test('a rejected change reverts and keeps the intended value', () async {
      unawaited(cubit.trustSelected());
      await _settle();
      fixture.likes.fail(0, const LikeSetException());
      await _settle();

      expect(cubit.state.selectedProfile!.myVote, 0);
      expect(patched.last.myVote, 0);
      final error = cubit.state.trustError;
      expect(error, isNotNull);
      expect((error as dynamic).intendedAmount, 1);
    });

    test('exhausted retries revert the change', () async {
      unawaited(cubit.trustSelected());
      await _settle();
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(fixture.likes.calls, hasLength(attempt + 1));
        final schedulesBeforeFailure = fixture.wakeUp.calls.length;
        fixture.likes.fail(attempt, _transport);
        await _settle();
        if (attempt < 2) {
          expect(fixture.likes.calls, hasLength(attempt + 1));
          final delay = expectR4RetryScheduled(
            fixture.wakeUp,
            schedulesBeforeFailure,
            attempt: attempt + 1,
          );
          fixture.wakeUp.elapse(delay - const Duration(milliseconds: 1));
          await _settle();
          expect(fixture.likes.calls, hasLength(attempt + 1));
          fixture.wakeUp.elapse(const Duration(milliseconds: 1));
          await _settle();
        }
      }

      expect(fixture.likes.amounts, [1, 1, 1]);
      expect(cubit.state.selectedProfile!.myVote, 0);
      expect(cubit.state.trustError, isNotNull);
    });

    test('retrying after a revert re-issues the intended value', () async {
      unawaited(cubit.trustSelected());
      await _settle();
      fixture.likes.fail(0, const LikeSetException());
      await _settle();

      unawaited(cubit.trustSelected());
      await _settle();

      expect(fixture.likes.amounts, [1, 1]);
      expect(cubit.state.selectedProfile!.myVote, 1);
      expect(cubit.state.trustError, isNull);
    });

    test('a late revert for Alice leaves the panel of Bob alone', () async {
      unawaited(cubit.trustSelected());
      await _settle();
      cubit.selectProfile(_bob, intentional: true);
      await _settle();

      fixture.likes.fail(0, const LikeSetException());
      await _settle();

      expect(cubit.state.selectedProfile!.id, 'Ubob');
      expect(cubit.state.selectedProfile!.myVote, 0);
      expect(patched.last.id, 'Ualice');
      expect(patched.last.myVote, 0);
      final rejection = cubit.state.trustError! as GraphTrustRevert;
      expect(rejection.peerId, 'Ualice');
      await cubit.retryTrust(rejection);
      expect(fixture.likes.amounts, [1, 1]);
      expect(cubit.state.selectedProfile!.id, 'Ubob');
      expect(cubit.state.selectedProfile!.myVote, 0);
    });

    test(
      'a settled graph write yields to a later profile-screen change',
      () async {
        await cubit.trustSelected();
        fixture.likes.ack(0);
        await _settle();
        expect(cubit.state.selectedProfile!.myVote, 1);

        // Use the profile screen's unchanged write-and-read flow.
        fixture.profiles.byId['Ualice'] = _alice;
        final profileChange = fixture.profileViewCase.removeFriend(
          cubit.state.selectedProfile!,
        );
        fixture.likes.ack(1);
        expect((await profileChange).myVote, 0);

        cubit.selectProfile(_bob, intentional: true);
        await _settle();
        cubit.selectProfile(_alice.copyWith(myVote: 1), intentional: true);
        await _settle();
        expect(cubit.state.selectedProfile!.myVote, 0);
        await cubit.trustSelected();
        expect(fixture.likes.amounts, [1, 0, 1]);
      },
    );

    test('authoritative reads preserve the pending latest intent', () async {
      await cubit.trustSelected();
      cubit.selectProfile(_bob, intentional: true);
      await _settle();
      cubit.selectProfile(_alice, intentional: true);
      await _settle();
      expect(cubit.state.selectedProfile!.myVote, 1);
      await cubit.untrustSelected();
      fixture.likes.ack(0);
      await _settle();
      expect(fixture.likes.amounts, [1, 0]);
      expect(cubit.state.selectedProfile!.myVote, 0);
    });

    test('Retry cannot replace a newer intent for the original peer', () async {
      await cubit.trustSelected();
      fixture.likes.fail(0, const LikeSetException());
      await _settle();
      final rejection = cubit.state.trustError! as GraphTrustRevert;
      await cubit.untrustSelected();
      cubit.selectProfile(_bob, intentional: true);
      await _settle();
      await cubit.retryTrust(rejection);
      expect(fixture.likes.amounts, [1]);
      expect(cubit.state.selectedProfile!.id, 'Ubob');
    });

    test('closing mid-flight causes no emit after close', () async {
      unawaited(cubit.trustSelected());
      await _settle();
      final lastState = cubit.state;

      await cubit.close();
      fixture.likes.fail(0, const LikeSetException());
      await _settle();

      expect(cubit.isClosed, isTrue);
      expect(cubit.state, lastState);
    });
  });
}
