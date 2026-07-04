import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_cubit.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_state.dart';

import '../auth/auth_test_helpers.dart';
import 'fcm_case_test.dart';

void main() {
  group('FcmCubit cold-start retry', () {
    test(
        'retries once after a short delay when the first sync finds no '
        'platform token yet (service worker registration race — see '
        'FcmCubit._scheduleColdStartRetry)', () {
      fakeAsync((async) {
        final local = FakeFcmLocal();
        final remote = FakeFcmRemote();
        final fcmCase = FcmCase(local, remote, FakeSettings(appId: 'app-1'));
        final authCase = buildTestAuthCase(
          _SignedInAuthLocal(),
          EmptyAuthRemote(),
        );

        // getToken() racing the still-registering service worker.
        local.token = null;
        final cubit = FcmCubit(fcmCase, authCase);
        addTearDown(cubit.close);

        async.flushMicrotasks();
        expect(remote.registerCalls, 0);
        expect(cubit.state.appId, isEmpty);

        // The service worker has finished registering by the time the
        // retry fires.
        local.token = 'fresh-token';
        async.elapse(const Duration(seconds: 3));

        expect(remote.registerCalls, 1);
        expect(remote.lastRegister?.token, 'fresh-token');
        expect(cubit.state.appId, 'app-1');
        expect(cubit.state.status, StateStatus.isSuccess);
      });
    });

    test('does not retry when the first sync already succeeded', () {
      fakeAsync((async) {
        final local = FakeFcmLocal();
        final remote = FakeFcmRemote();
        final fcmCase = FcmCase(local, remote, FakeSettings(appId: 'app-1'));
        final authCase = buildTestAuthCase(
          _SignedInAuthLocal(),
          EmptyAuthRemote(),
        );

        local.token = 'already-there';
        final cubit = FcmCubit(fcmCase, authCase);
        addTearDown(cubit.close);

        async.flushMicrotasks();
        expect(remote.registerCalls, 1);

        async.elapse(const Duration(seconds: 5));

        expect(remote.registerCalls, 1);
      });
    });
  });
}

class _SignedInAuthLocal extends EmptyAuthLocal {
  static const _accountId = 'Utest0000001';

  @override
  Stream<String> currentAccountChanges() => Stream.value(_accountId);

  @override
  Future<String> getCurrentAccountId() async => _accountId;
}
