import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/features/auth/domain/constellation_account_adapter.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';

import 'auth_test_helpers.dart';

void main() {
  group('ConstellationAccountAdapter', () {
    for (final currentAccount in ['account-a', '']) {
      test(
        currentAccount.isEmpty
            ? 'emits the initial signed-out account on subscription'
            : 'emits the current account without waiting for a change',
        () async {
          final accounts = BehaviorSubject<String>.seeded(currentAccount);
          addTearDown(accounts.close);
          final ConstellationAccountPort port = ConstellationAccountAdapter(
            buildTestAuthCase(
              _AccountsLocal(accounts.stream),
              EmptyAuthRemote(),
            ),
          );

          expect(await port.currentAccountChanges.first, currentAccount);
        },
      );
    }

    test('new subscriptions receive the latest current account', () async {
      final accounts = BehaviorSubject<String>.seeded('account-a');
      addTearDown(accounts.close);
      final ConstellationAccountPort port = ConstellationAccountAdapter(
        buildTestAuthCase(_AccountsLocal(accounts.stream), EmptyAuthRemote()),
      );

      expect(await port.currentAccountChanges.first, 'account-a');
      accounts.add('account-b');
      expect(await port.currentAccountChanges.first, 'account-b');
      accounts.add('');
      expect(await port.currentAccountChanges.first, '');
    });

    test(
      'exposes the authentication account changes as the account port',
      () async {
        final accounts = StreamController<String>();
        addTearDown(accounts.close);
        final ConstellationAccountPort port = ConstellationAccountAdapter(
          buildTestAuthCase(_AccountsLocal(accounts.stream), EmptyAuthRemote()),
        );
        final seen = <String>[];
        final subscription = port.currentAccountChanges.listen(seen.add);
        addTearDown(subscription.cancel);

        accounts
          ..add('account-a')
          ..add('');
        await pumpEventQueue();

        expect(seen, ['account-a', '']);
      },
    );

    test('forwards each account replacement in order', () async {
      final accounts = StreamController<String>();
      addTearDown(accounts.close);
      final port = ConstellationAccountAdapter(
        buildTestAuthCase(_AccountsLocal(accounts.stream), EmptyAuthRemote()),
      );
      final seen = <String>[];
      final subscription = port.currentAccountChanges.listen(seen.add);
      addTearDown(subscription.cancel);

      accounts
        ..add('account-a')
        ..add('account-b');
      await pumpEventQueue();

      expect(seen, ['account-a', 'account-b']);
    });

    test('preserves stream errors and subsequent account changes', () async {
      final accounts = StreamController<String>();
      addTearDown(accounts.close);
      final ConstellationAccountPort port = ConstellationAccountAdapter(
        buildTestAuthCase(_AccountsLocal(accounts.stream), EmptyAuthRemote()),
      );
      final error = StateError('account source failed');
      final stackTrace = StackTrace.current;
      final errors = <Object>[];
      final stackTraces = <StackTrace>[];
      final seen = <String>[];
      final subscription = port.currentAccountChanges.listen(
        seen.add,
        onError: (Object error, StackTrace stackTrace) {
          errors.add(error);
          stackTraces.add(stackTrace);
        },
      );
      addTearDown(subscription.cancel);

      accounts
        ..add('account-a')
        ..addError(error, stackTrace)
        ..add('account-b');
      await pumpEventQueue();

      expect(errors, [same(error)]);
      expect(stackTraces, [same(stackTrace)]);
      expect(seen, ['account-a', 'account-b']);
    });

    test('closes when the authentication account stream closes', () async {
      final accounts = StreamController<String>();
      addTearDown(accounts.close);
      final ConstellationAccountPort port = ConstellationAccountAdapter(
        buildTestAuthCase(_AccountsLocal(accounts.stream), EmptyAuthRemote()),
      );
      final completion = expectLater(
        port.currentAccountChanges,
        emitsInOrder(['account-a', emitsDone]),
      );

      accounts.add('account-a');
      await accounts.close();
      await completion;
    });
  });
}

class _AccountsLocal extends EmptyAuthLocal {
  _AccountsLocal(this._changes);

  final Stream<String> _changes;

  @override
  Stream<String> currentAccountChanges() => _changes;
}
