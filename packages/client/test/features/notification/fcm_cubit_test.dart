import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/notification/domain/entity/notification_permissions.dart';
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

  group('FcmCubit on web: no browser prompt on load (B065)', () {
    setUp(() => FcmCubit.debugAsksOnLoad = false);
    tearDown(() => FcmCubit.debugAsksOnLoad = null);

    ({FcmCubit cubit, FakeFcmLocal local, FakeFcmRemote remote,
        FakeSettings settings}) build(NotificationPermissionStatus status) {
      final local = FakeFcmLocal()
        ..status = status
        ..token = 'tok';
      final remote = FakeFcmRemote();
      final settings = FakeSettings(appId: 'app-1');
      final cubit = FcmCubit(
        FcmCase(local, remote, settings),
        buildTestAuthCase(_SignedInAuthLocal(), EmptyAuthRemote()),
      );
      return (cubit: cubit, local: local, remote: remote, settings: settings);
    }

    test('not asked yet: no prompt, no token, the in-app prompt shows', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.notDetermined);
        addTearDown(t.cubit.close);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 5));

        expect(t.local.requestPermissionCalls, 0);
        // Firebase's getToken() would itself ask the browser for permission.
        expect(t.local.getTokenCalls, 0);
        expect(t.remote.registerCalls, 0);
        expect(t.cubit.state.showsPermissionPrompt, isTrue);
        expect(t.cubit.state.permissions.authorized, isFalse);
        expect(t.cubit.state.status, StateStatus.isSuccess);
      });
    });

    test('tapping the prompt asks once and registers the device', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.notDetermined);
        t.local.permissionAfterRequest = NotificationPermissionStatus.granted;
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        unawaited(t.cubit.requestPermissionFromUser());
        async.flushMicrotasks();

        expect(t.local.requestPermissionCalls, 1);
        expect(t.remote.registerCalls, 1);
        expect(t.cubit.state.permissionStatus,
            NotificationPermissionStatus.granted);
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
        expect(t.cubit.state.appId, 'app-1');
      });
    });

    test('blocking in the browser dialog hides the prompt, registers nothing',
        () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.notDetermined);
        t.local
          ..permissionAfterRequest = NotificationPermissionStatus.denied
          ..permissionResult = const NotificationPermissions();
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        unawaited(t.cubit.requestPermissionFromUser());
        async.flushMicrotasks();

        expect(t.remote.registerCalls, 0);
        expect(t.cubit.state.permissionStatus,
            NotificationPermissionStatus.denied);
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
      });
    });

    test('a plugin error on "Turn on" is caught and the status re-read', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.notDetermined);
        t.local.requestPermissionError = StateError('plugin failed');
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        Object? escaped;
        runZonedGuarded(
          () => unawaited(t.cubit.requestPermissionFromUser()),
          (e, _) => escaped = e,
        );
        t.local.status = NotificationPermissionStatus.denied;
        async.flushMicrotasks();

        expect(escaped, isNull);
        expect(t.remote.registerCalls, 0);
        expect(t.cubit.state.permissionStatus,
            NotificationPermissionStatus.denied);
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
      });
    });

    test('"Not now" hides the prompt and is remembered on the device', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.notDetermined);
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        unawaited(t.cubit.dismissPermissionPrompt());
        async.flushMicrotasks();
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
        expect(t.settings.notificationPromptDismissed, isTrue);
        expect(t.local.requestPermissionCalls, 0);

        // Next start on the same device: still hidden.
        final again = FcmCubit(
          FcmCase(t.local, t.remote, t.settings),
          buildTestAuthCase(_SignedInAuthLocal(), EmptyAuthRemote()),
        );
        addTearDown(again.close);
        async.flushMicrotasks();
        expect(again.state.permissionStatus,
            NotificationPermissionStatus.notDetermined);
        expect(again.state.showsPermissionPrompt, isFalse);
      });
    });

    test('already denied: no prompt and no in-app prompt', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.denied);
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        expect(t.local.requestPermissionCalls, 0);
        expect(t.local.getTokenCalls, 0);
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
      });
    });

    test('already granted: registers as before, no in-app prompt', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.granted);
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        expect(t.remote.registerCalls, 1);
        expect(t.cubit.state.permissions.authorized, isTrue);
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
      });
    });

    test('unsupported browser or no push config: nothing to offer', () {
      fakeAsync((async) {
        final t = build(NotificationPermissionStatus.unsupported);
        addTearDown(t.cubit.close);
        async.flushMicrotasks();

        expect(t.local.requestPermissionCalls, 0);
        expect(t.cubit.state.showsPermissionPrompt, isFalse);
      });
    });
  });

  test('native keeps asking on account load (unchanged)', () {
    fakeAsync((async) {
      FcmCubit.debugAsksOnLoad = true;
      addTearDown(() => FcmCubit.debugAsksOnLoad = null);
      final local = FakeFcmLocal()
        ..status = NotificationPermissionStatus.notDetermined
        ..token = 'tok';
      final remote = FakeFcmRemote();
      final cubit = FcmCubit(
        FcmCase(local, remote, FakeSettings(appId: 'app-1')),
        buildTestAuthCase(_SignedInAuthLocal(), EmptyAuthRemote()),
      );
      addTearDown(cubit.close);
      async.flushMicrotasks();

      expect(local.requestPermissionCalls, 1);
      expect(remote.registerCalls, 1);
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
