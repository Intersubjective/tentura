// The plan specifies revert payloads, but does not bind an event class name.
// Validate their public fields without requiring another new production type.
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart'
    show kLazyWriteAckTimeout;
import 'package:tentura/features/like/domain/exception.dart';

import '../../support/graph_trust_write_fixture.dart';

const _alice = Profile(id: 'Ualice', displayName: 'Alice');
const _bob = Profile(id: 'Ubob', displayName: 'Bob');
const _carol = Profile(id: 'Ucarol', displayName: 'Carol');
const _aliceTrusted = Profile(id: 'Ualice', displayName: 'Alice', myVote: 1);
Future<void> _settle() => pumpEventQueue(times: 5);
final _transport = TimeoutException('no acknowledgement');

void main() {
  group('Account-owned graph trust writer', () {
    late GraphTrustWriteFixture fixture;
    late List<dynamic> reverts;
    late List<LazyWriteNotice> notices;

    setUp(() async {
      fixture = GraphTrustWriteFixture();
      reverts = [];
      notices = [];
      fixture.trustWriteCase.reverts.listen(reverts.add);
      fixture.trustWriteCase.lazyWriteNotices.listen(notices.add);
      await _settle();
    });
    tearDown(() => fixture.dispose());

    test(
      'trust sends one absolute value and never re-reads the profile',
      () async {
        final reads = fixture.profiles.fetchCalls;
        fixture.trustWriteCase.setTrust(_alice, add: true);
        await _settle();
        expect(fixture.likes.amounts, [1]);
        expect(fixture.likes.calls.single.id, 'Ualice');
        fixture.likes.ack(0);
        await _settle();
        expect(fixture.profiles.fetchCalls, reads);
        expect(fixture.likes.amounts, [1]);
        expect(reverts, isEmpty);
      },
    );

    test('withdrawing trust sends absolute zero without re-reading', () async {
      final reads = fixture.profiles.fetchCalls;
      fixture.trustWriteCase.setTrust(_aliceTrusted, add: false);
      await _settle();
      expect(fixture.likes.amounts, [0]);
      fixture.likes.ack(0);
      await _settle();
      expect(fixture.profiles.fetchCalls, reads);
      expect(reverts, isEmpty);
    });

    test('a toggle back waits behind the one request in flight', () async {
      fixture.trustWriteCase.setTrust(_alice, add: true);
      await _settle();
      fixture.trustWriteCase.setTrust(_alice, add: false);
      await _settle();
      expect(fixture.likes.amounts, [1]);
      fixture.likes.ack(0);
      await _settle();
      expect(fixture.likes.amounts, [1, 0]);
    });

    test('only the latest of several pending values is written next', () async {
      fixture.trustWriteCase.setTrust(_alice, add: true);
      await _settle();
      fixture.trustWriteCase
        ..setTrust(_alice, add: false)
        ..setTrust(_alice, add: true)
        ..setTrust(_alice, add: false);
      await _settle();
      expect(fixture.likes.amounts, [1]);
      fixture.likes.ack(0);
      await _settle();
      expect(fixture.likes.amounts, [1, 0]);
    });

    test(
      'a pending value equal to the acknowledgement is not resent',
      () async {
        fixture.trustWriteCase.setTrust(_alice, add: true);
        await _settle();
        fixture.trustWriteCase
          ..setTrust(_alice, add: false)
          ..setTrust(_alice, add: true);
        await _settle();
        expect(fixture.likes.amounts, [1]);
        fixture.likes.ack(0);
        await _settle();
        expect(fixture.likes.amounts, [1]);
      },
    );

    test('each peer has an independent in-flight write', () async {
      fixture.trustWriteCase
        ..setTrust(_alice, add: true)
        ..setTrust(_bob, add: true);
      await _settle();
      expect(fixture.likes.calls.map((c) => c.id), ['Ualice', 'Ubob']);
      fixture.likes.fail(0, const LikeSetException());
      fixture.likes.ack(1);
      await _settle();
      expect(reverts, hasLength(1));
      expect(reverts.single.peerId, 'Ualice');
      expect(reverts.single.acknowledgedAmount, 0);
      expect(reverts.single.intendedAmount, 1);
    });

    test('transport retry waits until the first R4 backoff deadline', () async {
      fixture.trustWriteCase.setTrust(_alice, add: true);
      await _settle();
      final schedulesBeforeFailure = fixture.wakeUp.calls.length;
      fixture.likes.fail(0, _transport);
      await _settle();
      expect(fixture.likes.amounts, [1], reason: 'no immediate retry');
      expect(reverts, isEmpty);
      final delay = expectR4RetryScheduled(
        fixture.wakeUp,
        schedulesBeforeFailure,
        attempt: 1,
      );
      fixture.wakeUp.elapse(delay - const Duration(milliseconds: 1));
      await _settle();
      expect(fixture.likes.amounts, [1]);
      fixture.wakeUp.elapse(const Duration(milliseconds: 1));
      await _settle();
      expect(fixture.likes.amounts, [1, 1]);
      fixture.likes.ack(1);
      await _settle();
      expect(reverts, isEmpty);
    });

    test(
      'later R4 backoff doubles before exhaustion at three attempts',
      () async {
        fixture.trustWriteCase.setTrust(_alice, add: true);
        await _settle();
        for (var attempt = 1; attempt <= 2; attempt++) {
          final schedulesBeforeFailure = fixture.wakeUp.calls.length;
          fixture.likes.fail(attempt - 1, _transport);
          await _settle();
          expect(
            fixture.likes.calls,
            hasLength(attempt),
            reason: 'retry must not be immediate',
          );
          expect(reverts, isEmpty);
          final delay = expectR4RetryScheduled(
            fixture.wakeUp,
            schedulesBeforeFailure,
            attempt: attempt,
          );
          fixture.wakeUp.elapse(delay - const Duration(milliseconds: 1));
          await _settle();
          expect(fixture.likes.calls, hasLength(attempt));
          fixture.wakeUp.elapse(const Duration(milliseconds: 1));
          await _settle();
          expect(fixture.likes.calls, hasLength(attempt + 1));
        }
        fixture.likes.fail(2, _transport);
        await _settle();
        expect(fixture.likes.amounts, [1, 1, 1]);
        expect(reverts, hasLength(1));
        expect(reverts.single.peerId, 'Ualice');
        expect(reverts.single.acknowledgedAmount, 0);
        expect(reverts.single.intendedAmount, 1);
        fixture.wakeUp.elapse(const Duration(minutes: 1));
        await _settle();
        expect(fixture.likes.amounts, [
          1,
          1,
          1,
        ], reason: 'no fourth automatic attempt');
      },
    );

    test('definitive rejection reverts and exposes the retry intent', () async {
      fixture.trustWriteCase.setTrust(_alice, add: true);
      await _settle();
      fixture.likes.fail(0, const LikeSetException());
      await _settle();
      expect(reverts, hasLength(1));
      expect(reverts.single.peerId, 'Ualice');
      expect(reverts.single.acknowledgedAmount, 0);
      expect(reverts.single.intendedAmount, 1);
      fixture.wakeUp.elapse(const Duration(minutes: 1));
      await _settle();
      expect(fixture.likes.amounts, [1]);
    });

    test('withdrawal rejection restores the last acknowledged trust', () async {
      fixture.trustWriteCase.setTrust(_alice, add: true);
      await _settle();
      fixture.likes.ack(0);
      await _settle();
      fixture.trustWriteCase.setTrust(_aliceTrusted, add: false);
      await _settle();
      fixture.likes.fail(1, const LikeSetException());
      await _settle();
      expect(reverts, hasLength(1));
      expect(reverts.single.acknowledgedAmount, 1);
      expect(reverts.single.intendedAmount, 0);
    });

    for (final nextAccount in ['', 'Uother']) {
      for (final lateResult in ['acknowledgement', 'transport failure']) {
        test(
          '${nextAccount.isEmpty ? 'logout' : 'account switch'} clears queued writes before a late $lateResult',
          () async {
            fixture.trustWriteCase.setTrust(_alice, add: true);
            await _settle();
            fixture.trustWriteCase.setTrust(_alice, add: false);
            await _settle();
            expect(fixture.likes.amounts, [1]);
            fixture.account.add(nextAccount);
            await _settle();
            if (lateResult == 'acknowledgement') {
              fixture.likes.ack(0);
            } else {
              fixture.likes.fail(0, _transport);
            }
            await _settle();
            fixture.wakeUp.elapse(const Duration(minutes: 1));
            await _settle();
            expect(fixture.likes.amounts, [1]);
            expect(reverts, isEmpty);
            expect(notices, isEmpty);
          },
        );
      }
    }

    group('Trust acknowledgement timeout', () {
      test(
        'a missing acknowledgement emits one domain notice at fifteen seconds',
        () async {
          expect(kLazyWriteAckTimeout, const Duration(seconds: 15));
          fixture.trustWriteCase.setTrust(_alice, add: true);
          await _settle();
          fixture.wakeUp.elapse(
            kLazyWriteAckTimeout - const Duration(milliseconds: 1),
          );
          await _settle();
          expect(notices, isEmpty);
          fixture.wakeUp.elapse(const Duration(milliseconds: 1));
          await _settle();
          expect(notices, hasLength(1));
          expect(notices.single, isA<LazyWriteNotice>());
          fixture.wakeUp.elapse(kLazyWriteAckTimeout);
          await _settle();
          expect(
            notices,
            hasLength(1),
            reason: 'one notice for the same overdue episode',
          );
        },
      );

      test(
        'an acknowledgement before the deadline prevents the domain notice',
        () async {
          fixture.trustWriteCase.setTrust(_alice, add: true);
          await _settle();
          fixture.wakeUp.elapse(const Duration(seconds: 10));
          fixture.likes.ack(0);
          await _settle();
          fixture.wakeUp.elapse(kLazyWriteAckTimeout * 2);
          await _settle();
          expect(notices, isEmpty);
        },
      );

      test(
        'three overdue peers in one burst emit only one domain notice',
        () async {
          fixture.trustWriteCase
            ..setTrust(_alice, add: true)
            ..setTrust(_bob, add: true)
            ..setTrust(_carol, add: true);
          await _settle();
          expect(fixture.likes.calls, hasLength(3));
          fixture.wakeUp.elapse(kLazyWriteAckTimeout);
          await _settle();
          expect(notices, hasLength(1));
          fixture.wakeUp.elapse(kLazyWriteAckTimeout);
          await _settle();
          expect(notices, hasLength(1));
        },
      );

      test(
        'a transport retry does not restart the domain notice deadline',
        () async {
          fixture.trustWriteCase.setTrust(_alice, add: true);
          await _settle();
          fixture.wakeUp.elapse(const Duration(seconds: 5));
          final schedulesBeforeFailure = fixture.wakeUp.calls.length;
          fixture.likes.fail(0, _transport);
          await _settle();
          final delay = expectR4RetryScheduled(
            fixture.wakeUp,
            schedulesBeforeFailure,
            attempt: 1,
          );
          fixture.wakeUp.elapse(delay);
          await _settle();
          expect(fixture.likes.amounts, [1, 1]);
          fixture.wakeUp.elapse(
            kLazyWriteAckTimeout -
                const Duration(seconds: 5) -
                delay -
                const Duration(milliseconds: 1),
          );
          await _settle();
          expect(notices, isEmpty);
          fixture.wakeUp.elapse(const Duration(milliseconds: 1));
          await _settle();
          expect(notices, hasLength(1));
        },
      );

      test(
        'a new overdue episode after settlement may emit another notice',
        () async {
          fixture.trustWriteCase.setTrust(_alice, add: true);
          await _settle();
          fixture.wakeUp.elapse(kLazyWriteAckTimeout);
          await _settle();
          expect(notices, hasLength(1));
          fixture.likes.ack(0);
          await _settle();
          fixture.trustWriteCase.setTrust(_aliceTrusted, add: false);
          await _settle();
          fixture.wakeUp.elapse(kLazyWriteAckTimeout);
          await _settle();
          expect(notices, hasLength(2));
        },
      );
    });
  });
}
