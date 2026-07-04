import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/notification/domain/entity/fcm_test_send_result.dart';
import 'package:tentura/features/notification/domain/entity/notification_permissions.dart';
import 'package:tentura/features/notification/domain/exception.dart';
import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_cubit.dart';
import 'package:tentura/features/settings/domain/entity/email_test_send_result.dart';
import 'package:tentura/features/settings/domain/port/email_test_remote_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/debug_settings_cubit.dart';
import 'package:tentura/features/settings/ui/message/debug_settings_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../notification/fcm_case_test.dart';

void main() {
  group('DebugSettingsCubit', () {
    late _FcmCaseSpy fcmCase;
    late FakeEmailTestRepository emailRepo;
    late FakeUiEffectPort effects;
    late DebugSettingsCubit cubit;

    setUp(() {
      fcmCase = _FcmCaseSpy(FakeFcmLocal(), FakeFcmRemote(), FakeSettings());
      emailRepo = FakeEmailTestRepository();
      effects = FakeUiEffectPort();
      final authCase = buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote());
      cubit = DebugSettingsCubit(
        fcmCase,
        authCase,
        FcmCubit(fcmCase, authCase),
        emailRepo,
        effects,
      );
    });

    tearDown(() => cubit.close());

    test('successful FCM test starts cooldown', () async {
      await cubit.sendTestNotification();

      expect(cubit.state.isFcmTestEnabled, isFalse);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmTestSentMessage>()),
      );
    });

    test('failed FCM test does not start cooldown', () async {
      fcmCase.testResult = const FcmTestSendResult(
        ok: false,
        devices: 0,
        sent: 0,
        mock: false,
        reason: 'no_devices',
      );

      await cubit.sendTestNotification();

      expect(cubit.state.isFcmTestEnabled, isTrue);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmTestNoDevicesMessage>()),
      );
    });

    test('successful email test starts cooldown', () async {
      await cubit.sendTestEmail();

      expect(cubit.state.isEmailTestEnabled, isFalse);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugEmailTestSentMessage>()),
      );
    });
  });

  group('DebugSettingsCubit.forceReregisterDevice', () {
    late _FcmCaseSpy fcmCase;
    late FakeUiEffectPort effects;
    late DebugSettingsCubit cubit;

    Future<void> setup({
      required bool signedIn,
      bool permissionGranted = true,
    }) async {
      fcmCase = _FcmCaseSpy(FakeFcmLocal(), FakeFcmRemote(), FakeSettings());
      fcmCase.local.token = 'device-token';
      fcmCase.local.permissionResult = NotificationPermissions(
        authorized: permissionGranted,
      );
      effects = FakeUiEffectPort();
      final authCase = buildTestAuthCase(
        signedIn ? _SignedInAuthLocal() : EmptyAuthLocal(),
        EmptyAuthRemote(),
      );
      cubit = DebugSettingsCubit(
        fcmCase,
        authCase,
        FcmCubit(fcmCase, authCase),
        FakeEmailTestRepository(),
        effects,
      );
    }

    tearDown(() => cubit.close());

    test('registers with the server and reports success', () async {
      await setup(signedIn: true);

      await cubit.forceReregisterDevice();

      expect(cubit.state.isForcingReregister, isFalse);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmForceReregisterSentMessage>()),
      );
    });

    test('reports permission denied without registering', () async {
      await setup(signedIn: true, permissionGranted: false);

      await cubit.forceReregisterDevice();

      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmForceReregisterPermissionDeniedMessage>()),
      );
    });

    test('reports no active account', () async {
      await setup(signedIn: false);

      await cubit.forceReregisterDevice();

      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmForceReregisterNoAccountMessage>()),
      );
    });

    test('reports server rejection', () async {
      await setup(signedIn: true);
      fcmCase.remote.registerThrows = const FcmRegistrationRejectedException();

      await cubit.forceReregisterDevice();

      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmForceReregisterRejectedMessage>()),
      );
    });
  });
}

class _FcmCaseSpy extends FcmCase {
  _FcmCaseSpy(this.local, this.remote, FakeSettings settings)
      : super(local, remote, settings);

  final FakeFcmLocal local;
  final FakeFcmRemote remote;

  FcmTestSendResult testResult = const FcmTestSendResult(
    ok: true,
    devices: 2,
    sent: 2,
    mock: false,
  );

  @override
  Future<FcmTestSendResult> sendTestNotification() async => testResult;
}

class _SignedInAuthLocal extends EmptyAuthLocal {
  static const _accountId = 'Utest0000001';

  @override
  Stream<String> currentAccountChanges() => Stream.value(_accountId);

  @override
  Future<String> getCurrentAccountId() async => _accountId;
}

class FakeEmailTestRepository implements EmailTestRemoteRepositoryPort {
  EmailTestSendResult result = const EmailTestSendResult(ok: true, mock: false);

  @override
  Future<EmailTestSendResult> sendTestEmail() async => result;
}
